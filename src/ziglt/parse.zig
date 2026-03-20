const std = @import("std");
const lexer = @import("lexer.zig");
const bytecode = @import("bytecode.zig");
const mem = @import("mem.zig");

const Token = lexer.Token;

pub const BinaryOp = enum {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    CompareEq,
    CompareNeq,
    CompareLt,
    CompareLe,
    CompareGt,
    CompareGe,
    And,
    Or,
    BitAnd,
    BitOr,
    BitXor,
    BitShiftL,
    BitShiftR,
};

pub const UnaryOp = enum {
    Neg,
};

pub const ASTNode = union(enum) {
    const Node = @This();

    immediate: ImmediatePrimitive,
    identifier: Identifier,
    binary: Binary,
    unary: Unary,

    const ImmediatePrimitive = union(enum) {
        uint: u128,
        float: f128,
        boolean: bool,
        string: []const u8,
        char: u8,
    };

    const Identifier = struct {
        lexme: []const u8,
    };

    const Binary = struct {
        op: BinaryOp,
        left: *Node,
        right: *Node,
    };

    const Unary = struct {
        op: UnaryOp,
        expr: *Node,
    };
};

const Precedence = enum(u8) {
    Lowest, // values
    Assign, // = += *= etc.
    Or,
    And,
    Compare,
    Bitwise, // & ^ | orelse catch
    BitShift, // << >>
    Sum, // + -
    Product, // * / %
    Prefix, // -X ~X !X &X
    Initializer, // X{}
    ErrorUnion, // a!b
    Accessor, // X() X[] X.Y X.* X.?
};

pub const ParserError = error{
    AllocationError,
};

pub const Parser = struct {
    const This = @This();

    allocator: mem.SlabAllocator(ASTNode),
    source: lexer.Source,
    window: [2]Token = [_]Token{ Token.Eof, Token.Eof },
    heldToken: ?Token = null,

    pub fn init(allocator: std.mem.Allocator, source: lexer.Source) !This {
        // TODO: make a dynamic version of the slab allocator
        const alloc = try mem.SlabAllocator(ASTNode).init(allocator, .{ .defaultObjectCapacity = 1024, .defaultStackCapacity = 512 });

        var inst = This{ .allocator = alloc, .source = source };
        inst.window[0] = lexer.tokenize(&inst.source);
        inst.window[1] = lexer.tokenize(&inst.source);
        return inst;
    }

    fn peek(this: *This) Token {
        if (this.heldToken) |tok| return tok;
        return this.window[0];
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

    fn putBack(this: *This, tok: Token) void {
        std.debug.assert(this.heldToken == null);
        this.heldToken = tok;
    }

    fn hasNext(this: *This) bool {
        return this.peek().id != .Eof;
    }

    fn newNode(this: *This, node: ASTNode) ParserError!*ASTNode {
        const ptr = this.allocator.create() catch return error.AllocationError;
        ptr.* = node;
        return ptr;
    }

    fn getPrec(id: lexer.TokenID) Precedence {
        return switch (id) {
            .Equal, .PlusEq, .MinusEq, .AsteriskEq, .ForwardSlEq, .PercentEq, .AmpEq, .PipeEq, .CaretEq, .LessLessEq, .GreaterGreaterEq => .Assign,
            .Or => .Or,
            .And => .And,
            .DoubleEqual, .NotEqual, .Less, .LessEqual, .Greater, .GreaterEqual => .Compare,
            .Amp, .Pipe, .Caret, .Orelse, .Catch => .Bitwise,
            .LessLess, .GreaterGreater => .BitShift,
            .Plus, .Minus => .Sum,
            .Asterisk, .ForwardSlash, .Percent => .Product,
            .LeftCurl => .Initializer,
            .Bang => .ErrorUnion,
            .LeftParen, .LeftBracket, .Period, .PeriodAst, .PeriodQuest => .Accessor,
            else => .Lowest,
        };
    }

    pub fn parse(this: *This) !*ASTNode {
        return try this.parseExpression(.Lowest);
    }

    fn parseExpression(this: *This, minPrec: Precedence) ParserError!*ASTNode {
        var left = try this.parsePrefix();
        errdefer this.allocator.free(left);

        while (this.hasNext() and @as(u8, @intFromEnum(getPrec(this.peek().id))) > @as(u8, @intFromEnum(minPrec))) {
            left = try this.parseInfix(left);
            errdefer this.allocator.free(left);
        }

        return left;
    }

    fn parsePrefix(this: *This) ParserError!*ASTNode {
        const tok = this.next();

        return switch (tok.id) {
            .ImmediateInteger => try this.newNode(.{
                .immediate = .{ .uint = std.fmt.parseInt(u128, this.source.getLexme(tok), 10) catch unreachable },
            }),

            .Minus => blk: {
                const expr = try this.parseExpression(.Prefix);
                break :blk try this.newNode(.{
                    .unary = .{
                        .op = .Neg,
                        .expr = expr,
                    },
                });
            },

            .LeftParen => blk: {
                const expr = try this.parseExpression(.Lowest);
                const closing = this.next();

                std.debug.assert(closing.id == .RightParen);

                break :blk expr;
            },
            else => unreachable,
        };
    }

    fn parseInfix(this: *This, left: *ASTNode) ParserError!*ASTNode {
        const tok = this.next();
        const prec = getPrec(tok.id);

        const right = try this.parseExpression(prec);

        return try this.newNode(.{
            .binary = .{
                .op = switch (tok.id) {
                    .Plus => .Add,
                    .Minus => .Sub,
                    .Asterisk => .Mul,
                    .ForwardSlash => .Div,
                    .Percent => .Mod,
                    .DoubleEqual => .CompareEq,
                    .NotEqual => .CompareNeq,
                    .Less => .CompareLt,
                    .LessEqual => .CompareLe,
                    .Greater => .CompareGt,
                    .GreaterEqual => .CompareGe,
                    .And => .And,
                    .Or => .Or,
                    .Amp => .BitAnd,
                    .Pipe => .BitOr,
                    .Caret => .BitXor,
                    .LessLess => .BitShiftL,
                    .GreaterGreater => .BitShiftR,
                    else => unreachable,
                },
                .left = left,
                .right = right,
            },
        });
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
    }
}

fn binaryOpToString(op: BinaryOp) []const u8 {
    return switch (op) {
        .Add => "+",
        .Sub => "-",
        .Mul => "*",
        .Div => "/",
        .Mod => "%",
        .CompareEq => "==",
        .CompareNeq => "!=",
        .CompareLt => "<",
        .CompareLe => "<=",
        .CompareGt => ">",
        .CompareGe => ">=",
        .And => "and",
        .Or => "or",
        .BitAnd => "&",
        .BitOr => "|",
        .BitXor => "^",
        .BitShiftL => "<<",
        .BitShiftR => ">>",
    };
}

fn unaryOpToString(op: UnaryOp) []const u8 {
    return switch (op) {
        .Neg => "-",
    };
}

fn nextPrefix(current: []const u8, is_last: bool) []const u8 {
    const suffix = if (is_last) "   " else "│  ";
    return std.mem.concat(std.heap.page_allocator, u8, &[_][]const u8{
        current,
        suffix,
    }) catch unreachable;
}

test "parser basic expression" {
    const src = lexer.Source.make("test", "1 * (2 + 199)");
    var parser = try Parser.init(std.testing.allocator, src);
    defer parser.allocator.deinit();
    const tree = try parser.parse();
    // No easy way to deep check the tree here without more helper functions,
    // but at least we can check it doesn't crash and returns something.
    try std.testing.expect(tree.* == .binary);
    try std.testing.expect(tree.binary.op == .Mul);
}

test "parser precedence" {
    const src = lexer.Source.make("test", "1 + 2 * 3 == 7");
    var parser = try Parser.init(std.testing.allocator, src);
    defer parser.allocator.deinit();
    const tree = try parser.parse();

    // 1 + (2 * 3) == 7
    // Tree: ( (1 + (2 * 3)) == 7 )
    try std.testing.expect(tree.* == .binary);
    try std.testing.expect(tree.binary.op == .CompareEq);
    try std.testing.expect(tree.binary.left.* == .binary);
    try std.testing.expect(tree.binary.left.binary.op == .Add);
    try std.testing.expect(tree.binary.left.binary.right.* == .binary);
    try std.testing.expect(tree.binary.left.binary.right.binary.op == .Mul);
}
