const std = @import("std");
const lexer = @import("lexer.zig");
const bytecode = @import("bytecode.zig");
const dispatch = @import("dispatch");

const Token = lexer.Token;
const Source = lexer.Source;
const TokenID = lexer.TokenID;

pub const BinaryOp = enum {
    Add,
    Subtract,
    Multiply,
    Divide,
    Modulus,
    CompareEq,
    CompareNeq,
    CompareLt,
    CompareLe,
    CompareGt,
    CompareGe,
    LogicalAnd,
    LogicalOr,
    BitwiseAnd,
    BitwiseOr,
    BitwiseXor,
    BitwiseShiftLeft,
    BitwiseShiftRight,
    Assign,
    NullUnwrap,
    ErrorUnion,
    // New operators
    ArrayMultiply,
    Orelse,
    Catch,
    FieldAccess,
    IndexAccess,
    AddAssign,
    SubtractAssign,
    MultiplyAssign,
    DivideAssign,
    ModulusAssign,
    BitwiseAndAssign,
    BitwiseOrAssign,
    BitwiseXorAssign,
    BitwiseShiftLeftAssign,
    BitwiseShiftRightAssign,
};

pub const UnaryOp = enum {
    Negation,
    LogicalNot,
    BitwiseNot,
    AddressOf,
    OptionalUnwrap,
    Dereference,
    Try,
};

pub const Visibility = enum { Default, Public };

pub const ASTNode = union(enum) {
    const Node = @This();

    immediate: ImmediatePrimitive,
    identifier: Identifier,
    binary: Binary,
    unary: Unary,
    @"if": If,
    @"while": While,
    @"for": For,
    @"switch": Switch,
    switchProng: SwitchProng,
    statement: Statement,
    capture: Capture,
    parameter: Parameter,
    argument: Argument,
    func: Func,
    declaration: Declaration,
    container: Container,
    @"enum": Enum,
    constDef: ConstDef,
    constRef: ConstRef,
    @"catch": Catch,
    @"defer": Defer,
    call: Call,
    interrupt: Interrupter,
    labelDefinition: LabelDefinition,
    labelReference: LabelReference,
    structInit: StructInitializer,
    arrayInit: ArrayInitializer,
    fieldInit: FieldInitializer,
    import: Import,
    type: Type,
    undefined,
    @"unreachable",

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

    const If = struct {
        condition: *Node,
        capture: ?*Capture,
        body: *Statement,
        elseBlock: ?*Statement,
    };

    const While = struct {
        condition: *Node,
        continueExpression: ?*Node,
        capture: ?*Capture,
        body: *Statement,
        elseBlock: ?*Statement,
    };

    const For = struct {
        collection: *Node,
        capture: ?*Capture,
        body: *Statement,
        elseBlock: ?*Statement,
    };

    const Switch = struct {
        const Prong = struct { case: *SwitchProng, next: ?*Prong };

        condition: *Node,
        prongs: *Prong,
    };

    const SwitchProng = struct {
        value: *Node,
        capture: ?*Capture,
        payload: ?*Node,
    };

    const Statement = struct {
        payload: *Node,
        next: ?*Statement,
    };

    // |a, b, c|
    const Capture = struct {
        identifier: *Identifier,
        next: ?*Capture,
    };

    // a: type
    const Parameter = struct {
        name: *Identifier,
        typeName: *Node,
        next: ?*Parameter,
    };

    const Argument = struct {
        expression: *Node,
        next: ?*Argument,
    };

    const Func = struct {
        visiblity: Visibility,
        isComptime: bool,
        name: ?*Identifier,
        parameters: ?*Parameter,
        returnType: *Node,
        body: *Statement,
        next: ?*Func,
    };

    const Declaration = struct {
        mode: Visibility,
        name: *Identifier,
        typeName: *Node,
        expression: *Node,
        next: ?*Declaration,
    };

    const Container = struct {
        pub const Kind = enum { Struct, Union, Enum };

        kind: Kind,
        visibility: Visibility,
        constants: ?*ConstDef,
        functions: ?*Func,
        members: ?*Declaration,
    };

    const Enum = struct {
        const Member = struct { name: *Identifier, value: ?*Node, next: ?*Member };

        visibility: Visibility,
        backing: ?*Node,
        members: ?*Member,
    };

    const ConstDef = struct {
        visibility: Visibility,
        name: *Identifier,
        payload: *Node,
        next: ?*ConstDef,
    };
    const ConstRef = struct {
        referenced: *ConstDef,
    };

    const Catch = struct {
        capture: ?*Capture,
        body: *Statement,
    };

    const Defer = struct {
        isError: bool,
        capture: ?*Capture,
        expression: *Node,
    };

    const Call = struct {
        name: *Node,
        args: ?*Argument,
    };

    const Interrupter = struct {
        pub const Kind = enum { Break, Continue, Return };
        kind: Kind,
        label: ?*LabelReference,
        value: ?*Node,
    };

    const LabelDefinition = struct {
        name: *Identifier,
    };
    const LabelReference = struct {
        name: *Identifier,
    };

    const StructInitializer = struct {
        const InitializerList = struct { field: *FieldInitializer, next: ?*InitializerList };

        typeName: *Node,
        initializers: ?*InitializerList,
    };

    const ArrayInitializer = struct {
        const Value = struct { expr: *Node, next: ?*Value };

        typeID: *Node,
        size: *Node,
        isConst: bool,
        values: *Value,
    };

    const FieldInitializer = struct {
        name: *Identifier,
        value: *Node,
    };

    const Import = struct {
        path: []const u8,
    };

    const Type = struct {
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
    UnexpectedToken,
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
        const ptr = try this.allocator.create(ASTNode);

        if (value) |val| {
            ptr.* = val;
        }

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

    fn expect(this: *This, id: lexer.TokenID) ?Token {
        if (this.peek().id == id) {
            return this.next;
        }
        return null;
    }

    fn parseExpression(this: *This, minPrec: Precedence) ParserError!*ASTNode {
        var left = try this.parsePrefix();

        while (this.hasNext() and @as(u8, @intFromEnum(getPrec(this.peek().id))) > @as(u8, @intFromEnum(minPrec))) {
            left = try this.parseInfix(left);
        }

        return left;
    }

    fn parsePrefix(this: *This) ParserError!*ASTNode {
        const tok = this.next();

        return switch (tok.id) {
            .ImmediateInteger => try this.makeNode(.{ .immediate = .{ .uint = std.fmt.parseInt(u128, this.source.getLexme(tok), 0) catch unreachable } }),
            .ImmediateFloat => try this.makeNode(.{ .immediate = .{ .float = std.fmt.parseFloat(f128, this.source.getLexme(tok)) catch unreachable } }),
            .True => try this.newNode(.{ .immediate = .{ .boolean = true } }),
            .False => try this.newNode(.{ .immediate = .{ .boolean = false } }),
            .ImmediateString => try this.newNode(.{ .immediate = .{ .string = this.source.getLexme(tok) } }),
            .ImmediateChar => try this.newNode(.{ .immediate = .{ .char = this.source.getLexme(tok)[1] } }), // TODO: fix char extraction to accept wide char literals
            .Identifier => try this.newNode(.{ .identifier = .{ .lexme = this.source.getLexme(tok) } }),
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
                break :blk try this.newNode(.{
                    .unary = .{
                        .op = op,
                        .expr = expr,
                    },
                });
            },
            .LeftParen => blk: {
                if (this.peek().id == .RightParen) {
                    return this.source.ReportError(error.UnexpectedToken, tok, null);
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
        const prec = getPrec(tok.id);

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
                break :blk try this.newNode(.{
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
                        const arg = try this.createNode(ASTNode.Argument, .{ .expression = arg_expr, .next = null });
                        if (last_arg) |l| l.next = arg else first_arg = arg;
                        last_arg = arg;
                        if (!this.match(.Comma)) break;
                    }
                }
                _ = try this.expect(.RightParen);
                break :blk try this.newNode(.{
                    .call = .{
                        .name = left,
                        .args = first_arg,
                    },
                });
            },

            .Period => blk: {
                const name_tok = try this.expect(.Identifier);
                const name = try this.newNode(.{ .identifier = .{ .lexme = this.source.getLexme(name_tok) } });
                break :blk try this.newNode(.{
                    .binary = .{
                        .op = .FieldAccess,
                        .left = left,
                        .right = name,
                    },
                });
            },

            .PeriodAst => try this.newNode(.{
                .unary = .{ .op = .Dereference, .expr = left },
            }),

            .PeriodQuest => try this.newNode(.{
                .unary = .{ .op = .OptionalUnwrap, .expr = left },
            }),

            .LeftBracket => blk: {
                const index = try this.parseExpression(.Lowest);
                _ = try this.expect(.RightBracket);
                break :blk try this.newNode(.{
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
