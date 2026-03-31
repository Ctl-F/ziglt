const std = @import("std");
const lexer = @import("lexer.zig");
const bytecode = @import("bytecode.zig");
const ast = @import("ast.zig");

const Token = lexer.Token;
const Source = lexer.Source;
const TokenID = lexer.TokenID;

pub const ASTNode = ast.ASTNode;
const Visibility = ast.Visibility;
const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;
const Precedence = ast.Precedence;

pub const ParserError = error{
    AllocationError,
    UnexpectedToken,
    OutOfMemory,
};

pub const Parser = struct {
    const This = @This();

    allocator: std.heap.ArenaAllocator,
    source: Source,
    window: [2]Token = [_]Token{ Token.Eof, Token.Eof },
    heldToken: ?Token = null,

    pub fn init(allocator: std.mem.Allocator, source: Source) !This {
        const alloc = std.heap.ArenaAllocator.init(allocator);

        var inst = This{ .allocator = alloc, .source = source };
        inst.window[0] = lexer.tokenize(&inst.source);
        inst.window[1] = lexer.tokenize(&inst.source);

        return inst;
    }

    fn peek(this: *This) Token {
        return this.heldToken orelse this.window[0];
    }

    fn next(this: *This) Token {
        if (this.heldToken) |tok| {
            this.heldToken = null;
            return tok;
        }

        const token = this.window[0];
        this.window[0] = this.window[1];
        this.window[1] = lexer.tokenize(&this.source);

        return token;
    }

    pub fn putBack(this: *This, tok: Token) void {
        std.debug.assert(this.heldToken == null);
        this.heldToken = tok;
    }

    fn hasNext(this: *This) bool {
        return this.peek().id != .Eof;
    }

    fn makeNode(this: *This, value: ?ASTNode) !*ASTNode {
        const ptr = try this.allocator.allocator().create(ASTNode);

        if (value) |val| {
            ptr.* = val;
        }

        return ptr;
    }

    fn expect(this: *This, id: lexer.TokenID) ?Token {
        if (this.peek().id == id) {
            return this.next();
        }
        return null;
    }

    // pub fn parse(this: *This) ParserError!*ASTNode {
    //     const tok = this.peek();
    //     if (tok.id == .Eof) return try this.makeNode(.undefined);
    // }

    pub fn parseExpression(this: *This, minPrec: Precedence) ParserError!*ASTNode {
        var left = try this.parsePrefix();

        while (this.hasNext() and @as(u8, @intFromEnum(Precedence.fromToken(this.peek().id))) > @as(u8, @intFromEnum(minPrec))) {
            left = try this.parseInfix(left);
        }

        return left;
    }

    fn parsePrefix(this: *This) ParserError!*ASTNode {
        const tok = this.next();

        return switch (tok.id) {
            .ImmediateInteger => try this.makeNode(.{ .immediate = .{ .uint = std.fmt.parseInt(u128, this.source.getLexme(tok), 0) catch unreachable } }),
            .ImmediateFloat => try this.makeNode(.{ .immediate = .{ .float = std.fmt.parseFloat(f128, this.source.getLexme(tok)) catch unreachable } }),
            .True => try this.makeNode(.{ .immediate = .{ .boolean = true } }),
            .False => try this.makeNode(.{ .immediate = .{ .boolean = false } }),
            .ImmediateString => try this.makeNode(.{ .immediate = .{ .string = this.source.getLexme(tok) } }),
            .ImmediateChar => try this.makeNode(.{ .immediate = .{ .char = this.source.getLexme(tok)[1] } }), // TODO: fix char extraction to accept wide char literals
            .Identifier => try this.makeNode(.{ .identifier = .{ .lexme = this.source.getLexme(tok) } }),
            .Minus, .Bang, .Tilde, .Amp, .Try => blk: {
                const op = switch (tok.id) {
                    .Minus => UnaryOp.Negation,
                    .Bang => UnaryOp.LogicalNot,
                    .Tilde => UnaryOp.BitwiseNot,
                    .Amp => UnaryOp.AddressOf,
                    .Try => UnaryOp.Try,
                    else => unreachable,
                };
                const expr = try this.parseExpression(.Prefix);
                break :blk try this.makeNode(.{
                    .unary = .{
                        .op = op,
                        .expr = expr,
                    },
                });
            },
            .LeftParen => blk: {
                if (this.peek().id == .RightParen) {
                    return this.source.reportError(error.UnexpectedToken, tok, null);
                }

                const expr = try this.parseExpression(.Lowest);
                if (this.expect(.RightParen) == null) {
                    return this.source.reportError(error.UnexpectedToken, tok, .RightParen);
                }
                break :blk expr;
            },

            else => {
                return this.source.reportError(error.UnexpectedToken, tok, null);
            },
        };
    }

    fn parseInfix(this: *This, left: *ASTNode) ParserError!*ASTNode {
        const tok = this.next();
        const prec = Precedence.fromToken(tok.id);

        return switch (tok.id) {
            .Plus, .Minus, .Asterisk, .ForwardSlash, .Percent, .DoubleEqual, .NotEqual, .Less, .LessEqual, .Greater, .GreaterEqual, .And, .Or, .Amp, .Pipe, .Caret, .LessLess, .GreaterGreater, .AsteriskAsterisk, .Orelse, .Catch, .Bang, .Equal, .PlusEq, .MinusEq, .AsteriskEq, .ForwardSlEq, .PercentEq, .AmpEq, .PipeEq, .CaretEq, .LessLessEq, .GreaterGreaterEq => blk: {
                const op = switch (tok.id) {
                    .Plus => BinaryOp.Add,
                    .Minus => BinaryOp.Subtract,
                    .Asterisk => BinaryOp.Multiply,
                    .ForwardSlash => BinaryOp.Divide,
                    .Percent => BinaryOp.Modulus,
                    .DoubleEqual => BinaryOp.CompareEq,
                    .NotEqual => BinaryOp.CompareNeq,
                    .Less => BinaryOp.CompareLt,
                    .LessEqual => BinaryOp.CompareLe,
                    .Greater => BinaryOp.CompareGt,
                    .GreaterEqual => BinaryOp.CompareGe,
                    .And => BinaryOp.LogicalAnd,
                    .Or => BinaryOp.LogicalOr,
                    .Amp => BinaryOp.BitwiseAnd,
                    .Pipe => BinaryOp.BitwiseOr,
                    .Caret => BinaryOp.BitwiseXor,
                    .LessLess => BinaryOp.BitwiseShiftLeft,
                    .GreaterGreater => BinaryOp.BitwiseShiftRight,
                    .AsteriskAsterisk => BinaryOp.ArrayMultiply,
                    .Orelse => BinaryOp.Orelse,
                    .Catch => BinaryOp.Catch,
                    .Bang => BinaryOp.ErrorUnion,
                    .Equal => BinaryOp.Assign,
                    .PlusEq => BinaryOp.AddAssign,
                    .MinusEq => BinaryOp.SubtractAssign,
                    .AsteriskEq => BinaryOp.MultiplyAssign,
                    .ForwardSlEq => BinaryOp.DivideAssign,
                    .PercentEq => BinaryOp.ModulusAssign,
                    .AmpEq => BinaryOp.BitwiseAndAssign,
                    .PipeEq => BinaryOp.BitwiseOrAssign,
                    .CaretEq => BinaryOp.BitwiseXorAssign,
                    .LessLessEq => BinaryOp.BitwiseShiftLeftAssign,
                    .GreaterGreaterEq => BinaryOp.BitwiseShiftRightAssign,
                    else => unreachable,
                };
                const right = try this.parseExpression(prec);
                break :blk try this.makeNode(.{
                    .binary = .{
                        .op = op,
                        .left = left,
                        .right = right,
                    },
                });
            },

            .LeftParen => blk: {
                var first_arg: ?*ASTNode.Argument = null;
                var last_arg: ?*ASTNode.Argument = null;
                if (this.peek().id != .RightParen) {
                    while (true) {
                        const arg_expr = try this.parseExpression(.Lowest);
                        var arg = try this.makeNode(.{ .argument = .{ .expression = arg_expr, .next = null } });
                        if (last_arg) |l| l.next = &arg.argument else first_arg = &arg.argument;
                        last_arg = &arg.argument;

                        if (this.expect(.Comma) != null) continue;
                        break;
                    }
                }
                if (this.expect(.RightParen) == null) {
                    return try this.source.reportError(error.UnexpectedToken, this.peek(), .RightParen);
                }
                break :blk try this.makeNode(.{
                    .call = .{
                        .name = left,
                        .args = first_arg,
                    },
                });
            },

            .Period => blk: {
                const name_tok = if (this.expect(.Identifier)) |id| id else return try this.source.reportError(error.UnexpectedToken, this.peek(), .Identifier);
                const name = try this.makeNode(.{ .identifier = .{ .lexme = this.source.getLexme(name_tok) } });
                break :blk try this.makeNode(.{
                    .binary = .{
                        .op = .FieldAccess,
                        .left = left,
                        .right = name,
                    },
                });
            },

            .PeriodAst => try this.makeNode(.{
                .unary = .{ .op = .Dereference, .expr = left },
            }),

            .PeriodQuest => try this.makeNode(.{
                .unary = .{ .op = .OptionalUnwrap, .expr = left },
            }),

            .LeftBracket => blk: {
                const index = try this.parseExpression(.Lowest);
                if (this.expect(.RightBracket) == null) return try this.source.reportError(error.UnexpectedToken, this.peek(), .RightBracket);
                break :blk try this.makeNode(.{
                    .binary = .{
                        .op = .IndexAccess,
                        .left = left,
                        .right = index,
                    },
                });
            },

            else => {
                return this.source.reportError(error.UnexpectedToken, tok, null);
            },
        };
    }
};

pub fn printAST(node: *const ASTNode) void {
    printNode(node, "", true);
}

fn printNode(node: *const ASTNode, prefix: []const u8, is_last: bool) void {
    // branch drawing
    if (prefix.len > 0) {
        std.debug.print("{s}", .{prefix});
        std.debug.print("{s}", .{if (is_last) "└─ " else "├─ "});
    }

    switch (node.*) {
        .immediate => |imm| {
            switch (imm) {
                .uint => |v| std.debug.print("Int({d})\n", .{v}),
                .float => |v| std.debug.print("Float({})\n", .{v}),
                .boolean => |v| std.debug.print("Bool({})\n", .{v}),
                .string => |v| std.debug.print("String(\"{s}\")\n", .{v}),
                .char => |v| std.debug.print("Char({d})\n", .{v}),
            }
        },

        .identifier => |ident| {
            std.debug.print("Ident({s})\n", .{ident.lexme});
        },

        .unary => |u| {
            std.debug.print("Unary({s})\n", .{unaryOpToString(u.op)});
            const new_prefix = nextPrefix(prefix, is_last);
            printNode(u.expr, new_prefix, true);
        },

        .binary => |b| {
            std.debug.print("Binary({s})\n", .{binaryOpToString(b.op)});
            const new_prefix = nextPrefix(prefix, is_last);
            printNode(b.left, new_prefix, false);
            printNode(b.right, new_prefix, true);
        },

        .@"if" => |i| {
            std.debug.print("If\n", .{});
            const new_prefix = nextPrefix(prefix, is_last);
            printNode(i.condition, new_prefix, false);
            printStatementList(i.body, new_prefix, i.elseBlock == null);
            if (i.elseBlock) |eb| {
                printStatementList(eb, new_prefix, true);
            }
        },
        .@"while" => |w| {
            std.debug.print("While\n", .{});
            const new_prefix = nextPrefix(prefix, is_last);
            printNode(w.condition, new_prefix, false);
            if (w.continueExpression) |c| printNode(c, new_prefix, false);
            printStatementList(w.body, new_prefix, w.elseBlock == null);
            if (w.elseBlock) |eb| {
                printStatementList(eb, new_prefix, true);
            }
        },
        .func => |f| {
            std.debug.print("Func({s})\n", .{if (f.name) |n| n.lexme else "anonymous"});
            const new_prefix = nextPrefix(prefix, is_last);
            var curr = f.parameters;
            while (curr) |p| {
                std.debug.print("{s}", .{new_prefix});
                std.debug.print("├─ Param({s})\n", .{p.name.lexme});
                printNode(p.typeName, nextPrefix(new_prefix, false), true);
                curr = p.next;
            }
            printNode(f.returnType, new_prefix, false);
            printStatementList(f.body, new_prefix, true);
        },
        .declaration => |d| {
            std.debug.print("Decl({s})\n", .{d.name.lexme});
            const new_prefix = nextPrefix(prefix, is_last);
            printNode(d.typeName, new_prefix, false);
            printNode(d.expression, new_prefix, true);
        },
        .statement => |s| {
            std.debug.print("Block\n", .{});
            printStatementList(&s, prefix, is_last);
        },
        .call => |c| {
            std.debug.print("Call\n", .{});
            const new_prefix = nextPrefix(prefix, is_last);
            printNode(c.name, new_prefix, c.args == null);
            var curr = c.args;
            while (curr) |a| {
                printNode(a.expression, new_prefix, a.next == null);
                curr = a.next;
            }
        },
        .interrupt => |i| {
            std.debug.print("Interrupt({s})\n", .{@tagName(i.kind)});
            if (i.value) |v| {
                const new_prefix = nextPrefix(prefix, is_last);
                printNode(v, new_prefix, true);
            }
        },
        .@"defer" => |d| {
            std.debug.print("Defer({s})\n", .{if (d.isError) "errdefer" else "defer"});
            const new_prefix = nextPrefix(prefix, is_last);
            printNode(d.expression, new_prefix, true);
        },
        .type => |t| {
            std.debug.print("TypeNode\n", .{});
            const new_prefix = nextPrefix(prefix, is_last);
            printNode(t.expr, new_prefix, true);
        },
        .undefined => std.debug.print("Undefined\n", .{}),
        .@"unreachable" => std.debug.print("Unreachable\n", .{}),
        else => std.debug.print("Node({s})\n", .{@tagName(node.*)}),
    }
}

fn binaryOpToString(op: BinaryOp) []const u8 {
    return switch (op) {
        .Add => "+",
        .Subtract => "-",
        .Multiply => "*",
        .Divide => "/",
        .Modulus => "%",
        .CompareEq => "==",
        .CompareNeq => "!=",
        .CompareLt => "<",
        .CompareLe => "<=",
        .CompareGt => ">",
        .CompareGe => ">=",
        .LogicalAnd => "and",
        .LogicalOr => "or",
        .BitwiseAnd => "&",
        .BitwiseOr => "|",
        .BitwiseXor => "^",
        .BitwiseShiftLeft => "<<",
        .BitwiseShiftRight => ">>",
        .Assign => "=",
        .NullUnwrap => ".?",
        .ErrorUnion => "!",
        .ArrayMultiply => "**",
        .Orelse => "orelse",
        .Catch => "catch",
        .FieldAccess => ".",
        .IndexAccess => "[]",
        .AddAssign => "+=",
        .SubtractAssign => "-=",
        .MultiplyAssign => "*=",
        .DivideAssign => "/=",
        .ModulusAssign => "%=",
        .BitwiseAndAssign => "&=",
        .BitwiseOrAssign => "|=",
        .BitwiseXorAssign => "^=",
        .BitwiseShiftLeftAssign => "<<=",
        .BitwiseShiftRightAssign => ">>=",
    };
}

fn unaryOpToString(op: UnaryOp) []const u8 {
    return switch (op) {
        .Negation => "-",
        .LogicalNot => "!",
        .BitwiseNot => "~",
        .AddressOf => "&",
        .OptionalUnwrap => ".?",
        .Dereference => ".*",
        .Try => "try",
    };
}

fn nextPrefix(current: []const u8, is_last: bool) []const u8 {
    const suffix = if (is_last) "   " else "│  ";
    return std.mem.concat(std.heap.page_allocator, u8, &[_][]const u8{
        current,
        suffix,
    }) catch unreachable;
}

fn printStatementList(first: *const ASTNode.Statement, prefix: []const u8, is_last: bool) void {
    var curr: ?*const ASTNode.Statement = first;
    const new_prefix = nextPrefix(prefix, is_last);
    while (curr) |s| {
        parseNode(s.payload, new_prefix, s.next == null);
        curr = s.next;
    }
}
fn parseNode(node: *const ASTNode, prefix: []const u8, is_last: bool) void {
    _ = prefix;
    _ = is_last;
    std.debug.print("Node({s})\n", .{@tagName(node.*)});
}
