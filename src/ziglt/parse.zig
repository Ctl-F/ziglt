const std = @import("std");
const lexer = @import("lexer.zig");
const bytecode = @import("bytecode.zig");
const mem = @import("mem.zig");

const Token = lexer.Token;

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

    fn createNode(this: *This, comptime T: type, initializer: T) ParserError!*T {
        const ptr = this.allocator.baseAllocator.create(T) catch return error.AllocationError;
        ptr.* = initializer;
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

    fn parseStatement(this: *This) ParserError!*ASTNode {
        const tok = this.peek();
        switch (tok.id) {
            .Pub => {
                _ = this.next();
                const node = try this.parseStatement();
                // For now, only handle Func and Var/Const with Pub.
                // We'd need to update the node's visibility field.
                switch (node.*) {
                    .func => |*f| f.visiblity = .Public,
                    .declaration => |*d| d.mode = .Public,
                    else => {},
                }
                return node;
            },
            .Import => {
                const node = try this.parseExpression(.Lowest);
                // Consume semicolon if it exists, but don't require it if we're at a RightCurl/RightParen (likely an expression context)
                if (this.peek().id == .Semicolon) {
                    _ = this.next();
                } else if (this.peek().id != .RightCurl and this.peek().id != .RightParen and this.peek().id != .Comma) {
                     // If it's not a common expression end, it might be a missing semicolon in a statement context
                     _ = try this.expect(.Semicolon);
                }
                return node;
            },
            .Struct, .Union, .Enum => {
                const kind_tok = this.next();
                const kind: ASTNode.Container.Kind = switch (kind_tok.id) {
                    .Struct => .Struct,
                    .Union => .Union,
                    .Enum => .Enum,
                    else => unreachable,
                };
                
                _ = try this.expect(.LeftCurl);
                
                var first_const: ?*ASTNode.ConstDef = null;
                var last_const: ?*ASTNode.ConstDef = null;
                var first_func: ?*ASTNode.Func = null;
                var last_func: ?*ASTNode.Func = null;
                var first_member: ?*ASTNode.Declaration = null;
                var last_member: ?*ASTNode.Declaration = null;
                
                while (this.peek().id != .RightCurl) {
                    const stmt = try this.parseStatement();
                    switch (stmt.*) {
                        .declaration => |*decl| {
                            const node = try this.createNode(ASTNode.Declaration, decl.*);
                            if (last_member) |l| l.next = node else first_member = node;
                            last_member = node;
                        },
                        .func => |*func| {
                            const node = try this.createNode(ASTNode.Func, func.*);
                            if (last_func) |l| l.next = node else first_func = node;
                            last_func = node;
                        },
                        .constDef => |*c| {
                            const node = try this.createNode(ASTNode.ConstDef, c.*);
                            if (last_const) |l| l.next = node else first_const = node;
                            last_const = node;
                        },
                        else => {}, // Ignore other statements in containers for now
                    }
                }
                _ = try this.expect(.RightCurl);
                
                if (kind == .Enum) {
                    return try this.newNode(.{ .@"enum" = .{ .visibility = .Default, .backing = null, .members = null } });
                }
                return try this.newNode(.{ 
                    .container = .{ 
                        .kind = kind, 
                        .visibility = .Default, 
                        .constants = first_const, 
                        .functions = first_func, 
                        .members = first_member 
                    } 
                });
            },
            .Var, .Const => {
                _ = this.next();
                const name_tok = try this.expect(.Identifier);
                const name = try this.newNode(.{ .identifier = .{ .lexme = this.source.getLexme(name_tok) } });

                var type_node: ?*ASTNode = null;
                if (this.match(.Colon)) {
                    type_node = try this.parseType();
                }

                var init_node: ?*ASTNode = null;
                if (this.match(.Equal)) {
                    init_node = try this.parseExpression(.Lowest);
                }

                // Consume semicolon if it exists, or if we're in a container/block end
                if (this.match(.Semicolon)) {
                    // good
                } else if (this.peek().id != .RightCurl and this.peek().id != .Comma and this.peek().id != .RightParen) {
                     _ = try this.expect(.Semicolon);
                }

                return try this.newNode(.{
                    .declaration = .{
                        .mode = .Default,
                        .name = &name.identifier,
                        .typeName = type_node orelse try this.newNode(.undefined),
                        .expression = init_node orelse try this.newNode(.undefined),
                        .next = null,
                    },
                });
            },
            .Fn => {
                _ = this.next();
                const name_tok = try this.expect(.Identifier);
                const name = try this.newNode(.{ .identifier = .{ .lexme = this.source.getLexme(name_tok) } });

                _ = try this.expect(.LeftParen);
                var first_param: ?*ASTNode.Parameter = null;
                var last_param: ?*ASTNode.Parameter = null;
                if (this.peek().id != .RightParen) {
                    while (true) {
                        const p_name_tok = try this.expect(.Identifier);
                        const p_name = try this.newNode(.{ .identifier = .{ .lexme = this.source.getLexme(p_name_tok) } });
                        _ = try this.expect(.Colon);
                        const p_type = try this.parseType();
                        const param = try this.createNode(ASTNode.Parameter, .{
                            .name = &p_name.identifier,
                            .typeName = p_type,
                            .next = null,
                        });
                        if (last_param) |l| l.next = param else first_param = param;
                        last_param = param;
                        if (!this.match(.Comma)) break;
                    }
                }
                _ = try this.expect(.RightParen);

                const ret_type = try this.parseType();
                const body = try this.parseBlock();

                return try this.newNode(.{
                    .func = .{
                        .visiblity = .Default,
                        .isComptime = false,
                        .name = &name.identifier,
                        .parameters = first_param,
                        .returnType = ret_type,
                        .body = body,
                        .next = null,
                    },
                });
            },
            .LeftCurl => {
                const body = try this.parseBlock();
                return try this.newNode(.{ .statement = body.* });
            },
            .Return, .Break, .Continue => {
                const kind_tok = this.next();
                const kind: ASTNode.Interrupter.Kind = switch (kind_tok.id) {
                    .Return => .Return,
                    .Break => .Break,
                    .Continue => .Continue,
                    else => unreachable,
                };

                var val: ?*ASTNode = null;
                if (kind == .Return and this.peek().id != .Semicolon) {
                    val = try this.parseExpression(.Lowest);
                }
                _ = try this.expect(.Semicolon);

                return try this.newNode(.{
                    .interrupt = .{
                        .kind = kind,
                        .label = null,
                        .value = val,
                    },
                });
            },
            .Defer, .Errdefer => {
                const is_err = this.next().id == .Errdefer;
                // Capture list |...|
                var first_cap: ?*ASTNode.Capture = null;
                var last_cap: ?*ASTNode.Capture = null;
                if (this.match(.Pipe)) {
                    while (this.peek().id != .Pipe) {
                        const cap_tok = try this.expect(.Identifier);
                        const cap_ident = try this.newNode(.{ .identifier = .{ .lexme = this.source.getLexme(cap_tok) } });
                        const cap = try this.createNode(ASTNode.Capture, .{
                            .identifier = &cap_ident.identifier,
                            .next = null,
                        });
                        if (last_cap) |l| l.next = cap else first_cap = cap;
                        last_cap = cap;
                        if (!this.match(.Comma)) break;
                    }
                    _ = try this.expect(.Pipe);
                }

                const expr = try this.parseExpression(.Lowest);
                _ = try this.expect(.Semicolon);
                
                return try this.newNode(.{
                    .@"defer" = .{
                        .isError = is_err,
                        .capture = first_cap,
                        .expression = expr,
                    },
                });
            },
            .Switch => {
                _ = this.next();
                _ = try this.expect(.LeftParen);
                const cond = try this.parseExpression(.Lowest);
                _ = try this.expect(.RightParen);
                _ = try this.expect(.LeftCurl);
                
                var first_prong: ?*ASTNode.Switch.Prong = null;
                var last_prong: ?*ASTNode.Switch.Prong = null;
                
                while (this.peek().id != .RightCurl) {
                    const case = try this.parseExpression(.Lowest);
                    var capture: ?*ASTNode.Capture = null;
                    if (this.match(.Pipe)) {
                        const cap_tok = try this.expect(.Identifier);
                        const cap_ident = try this.newNode(.{ .identifier = .{ .lexme = this.source.getLexme(cap_tok) } });
                        capture = try this.createNode(ASTNode.Capture, .{ .identifier = &cap_ident.identifier, .next = null });
                        _ = try this.expect(.Pipe);
                    }
                    _ = try this.expect(.GreaterEqual); // Case delimiter => or similar
                    const payload = try this.parseExpression(.Lowest);
                    if (this.peek().id == .Comma) _ = this.next();

                    const prong_node = try this.createNode(ASTNode.SwitchProng, .{
                        .value = case,
                        .capture = capture,
                        .payload = payload,
                    });
                    const prong = try this.createNode(ASTNode.Switch.Prong, .{ .case = prong_node, .next = null });
                    if (last_prong) |l| l.next = prong else first_prong = prong;
                    last_prong = prong;
                }
                _ = try this.expect(.RightCurl);
                
                return try this.newNode(.{
                    .@"switch" = .{
                        .condition = cond,
                        .prongs = first_prong orelse return error.UnexpectedToken,
                    },
                });
            },
            .For => {
                _ = this.next();
                _ = try this.expect(.LeftParen);
                const collection = try this.parseExpression(.Lowest);
                _ = try this.expect(.RightParen);
                
                var capture: ?*ASTNode.Capture = null;
                if (this.match(.Pipe)) {
                    const cap_tok = try this.expect(.Identifier);
                    const cap_ident = try this.newNode(.{ .identifier = .{ .lexme = this.source.getLexme(cap_tok) } });
                    capture = try this.createNode(ASTNode.Capture, .{ .identifier = &cap_ident.identifier, .next = null });
                    _ = try this.expect(.Pipe);
                }

                const body = try this.parseBlock();
                var else_block: ?*ASTNode.Statement = null;
                if (this.match(.Else)) {
                    else_block = try this.parseBlock();
                }
                
                return try this.newNode(.{
                    .@"for" = .{
                        .collection = collection,
                        .capture = capture,
                        .body = body,
                        .elseBlock = else_block,
                    },
                });
            },
            else => {
                const expr = try this.parseExpression(.Lowest);
                _ = try this.expect(.Semicolon);
                return expr;
            },
        }
    }

    fn parseType(this: *This) ParserError!*ASTNode {
        const tok = this.peek();
        switch (tok.id) {
            .Question => {
                _ = this.next();
                const child = try this.parseType();
                return try this.newNode(.{ .type = .{ .expr = child } });
            },
            .Asterisk => {
                _ = this.next();
                const child = try this.parseType();
                return try this.newNode(.{ .type = .{ .expr = child } });
            },
            .LeftBracket => {
                _ = this.next();
                if (this.match(.RightBracket)) {
                    const child = try this.parseType();
                    return try this.newNode(.{ .type = .{ .expr = child } });
                } else {
                    _ = try this.parseExpression(.Lowest);
                    _ = try this.expect(.RightBracket);
                    const child = try this.parseType();
                    // We need to store the size expression somewhere if we want to support fixed-size arrays.
                    // For now, let's just use the child to keep it simple as requested.
                    return try this.newNode(.{ .type = .{ .expr = child } });
                }
            },
            else => {
                const expr = try this.parseExpression(.Accessor);
                return try this.newNode(.{ .type = .{ .expr = expr } });
            },
        }
    }

    fn match(this: *This, id: lexer.TokenID) bool {
        if (this.peek().id == id) {
            _ = this.next();
            return true;
        }
        return false;
    }

    fn expect(this: *This, id: lexer.TokenID) !Token {
        const tok = this.next();
        if (tok.id != id) {
            std.debug.print("Expected {s}, got {s}\n", .{ @tagName(id), @tagName(tok.id) });
            return error.UnexpectedToken;
        }
        return tok;
    }

    fn parseExpression(this: *This, minPrec: Precedence) ParserError!*ASTNode {
        var left = try this.parsePrefix();

        while (this.hasNext() and @as(u8, @intFromEnum(getPrec(this.peek().id))) > @as(u8, @intFromEnum(minPrec))) {
            left = try this.parseInfix(left);
        }

        return left;
    }

    pub fn parse(this: *This) !*ASTNode {
        const tok = this.peek();
        if (tok.id == .Eof) return try this.newNode(.undefined);

        var first_stmt: ?*ASTNode.Statement = null;
        var last_stmt: ?*ASTNode.Statement = null;

        while (this.hasNext()) {
            const node = try this.parseStatement();
            const stmt = try this.createNode(ASTNode.Statement, .{ .payload = node, .next = null });
            if (last_stmt) |last| {
                last.next = stmt;
            } else {
                first_stmt = stmt;
            }
            last_stmt = stmt;
        }
        
        if (first_stmt) |first| {
            return try this.newNode(.{ .statement = first.* });
        }
        return try this.newNode(.undefined);
    }

    fn parsePrefix(this: *This) ParserError!*ASTNode {
        const tok = this.next();

        return switch (tok.id) {
            .ImmediateInteger => try this.newNode(.{
                .immediate = .{ .uint = std.fmt.parseInt(u128, this.source.getLexme(tok), 0) catch unreachable },
            }),
            .ImmediateFloat => try this.newNode(.{
                .immediate = .{ .float = std.fmt.parseFloat(f128, this.source.getLexme(tok)) catch unreachable },
            }),
            .True => try this.newNode(.{ .immediate = .{ .boolean = true } }),
            .False => try this.newNode(.{ .immediate = .{ .boolean = false } }),
            .ImmediateString => try this.newNode(.{ .immediate = .{ .string = this.source.getLexme(tok) } }),
            .ImmediateChar => try this.newNode(.{ .immediate = .{ .char = this.source.getLexme(tok)[1] } }), // Basic character extraction

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
                    _ = this.next();
                    // Handle () as a special node if needed
                    break :blk try this.newNode(.undefined);
                }
                const expr = try this.parseExpression(.Lowest);
                _ = try this.expect(.RightParen);
                break :blk expr;
            },

            .If => blk: {
                _ = try this.expect(.LeftParen);
                const cond = try this.parseExpression(.Lowest);
                _ = try this.expect(.RightParen);

                var capture: ?*ASTNode.Capture = null;
                if (this.match(.Pipe)) {
                    const name_tok = try this.expect(.Identifier);
                    const name_ident = try this.newNode(.{ .identifier = .{ .lexme = this.source.getLexme(name_tok) } });
                    _ = try this.expect(.Pipe);
                    capture = try this.createNode(ASTNode.Capture, .{
                        .identifier = &name_ident.identifier,
                        .next = null,
                    });
                }

                const body = try this.parseBlock();
                var else_block: ?*ASTNode.Statement = null;
                if (this.match(.Else)) {
                    if (this.peek().id == .If) {
                        const else_if = try this.parsePrefix(); // recurse if
                        else_block = try this.createNode(ASTNode.Statement, .{ .payload = else_if, .next = null });
                    } else {
                        else_block = try this.parseBlock();
                    }
                }
                break :blk try this.newNode(.{
                    .@"if" = .{
                        .condition = cond,
                        .capture = capture,
                        .body = body,
                        .elseBlock = else_block,
                    },
                });
            },
            
            .While => blk: {
                _ = try this.expect(.LeftParen);
                const cond = try this.parseExpression(.Lowest);
                _ = try this.expect(.RightParen);

                var capture: ?*ASTNode.Capture = null;
                if (this.match(.Pipe)) {
                    const name_tok = try this.expect(.Identifier);
                    const name_ident = try this.newNode(.{ .identifier = .{ .lexme = this.source.getLexme(name_tok) } });
                    _ = try this.expect(.Pipe);
                    capture = try this.createNode(ASTNode.Capture, .{
                        .identifier = &name_ident.identifier,
                        .next = null,
                    });
                }
                
                var cont: ?*ASTNode = null;
                if (this.match(.Colon)) {
                    _ = try this.expect(.LeftParen);
                    cont = try this.parseExpression(.Lowest);
                    _ = try this.expect(.RightParen);
                }

                const body = try this.parseBlock();
                var else_block: ?*ASTNode.Statement = null;
                if (this.match(.Else)) {
                    else_block = try this.parseBlock();
                }

                break :blk try this.newNode(.{
                    .@"while" = .{
                        .condition = cond,
                        .continueExpression = cont,
                        .capture = capture,
                        .body = body,
                        .elseBlock = else_block,
                    },
                });
            },

            .For => blk: {
                _ = try this.expect(.LeftParen);
                const collection = try this.parseExpression(.Lowest);
                _ = try this.expect(.RightParen);

                var capture: ?*ASTNode.Capture = null;
                if (this.match(.Pipe)) {
                    const name_tok = try this.expect(.Identifier);
                    const name_ident = try this.newNode(.{ .identifier = .{ .lexme = this.source.getLexme(name_tok) } });
                    _ = try this.expect(.Pipe);
                    capture = try this.createNode(ASTNode.Capture, .{
                        .identifier = &name_ident.identifier,
                        .next = null,
                    });
                }

                const body = try this.parseBlock();
                var else_block: ?*ASTNode.Statement = null;
                if (this.match(.Else)) {
                    else_block = try this.parseBlock();
                }

                break :blk try this.newNode(.{
                    .@"for" = .{
                        .collection = collection,
                        .capture = capture,
                        .body = body,
                        .elseBlock = else_block,
                    },
                });
            },

            .Defer, .Errdefer => blk: {
                const is_err = tok.id == .Errdefer;
                
                var capture: ?*ASTNode.Capture = null;
                if (this.match(.Pipe)) {
                    const name_tok = try this.expect(.Identifier);
                    const name_ident = try this.newNode(.{ .identifier = .{ .lexme = this.source.getLexme(name_tok) } });
                    _ = try this.expect(.Pipe);
                    capture = try this.createNode(ASTNode.Capture, .{
                        .identifier = &name_ident.identifier,
                        .next = null,
                    });
                }

                const expr = try this.parseExpression(.Lowest);
                break :blk try this.newNode(.{
                    .@"defer" = .{
                        .isError = is_err,
                        .capture = capture,
                        .expression = expr,
                    },
                });
            },

            .Import => blk: {
                _ = this.next();
                const has_paren = this.match(.LeftParen);
                const path_tok = try this.expect(.ImmediateString);
                const path = this.source.getLexme(path_tok);
                if (has_paren) _ = try this.expect(.RightParen);
                break :blk try this.newNode(.{ .import = .{ .path = path } });
            },

            .LeftCurl => blk: {
                const body = try this.parseBlock();
                break :blk try this.newNode(.{ .statement = body.* });
            },

            else => {
                std.debug.print("Unexpected token in parsePrefix: {s}\n", .{@tagName(tok.id)});
                return error.UnexpectedToken;
            },
        };
    }

    fn parseBlock(this: *This) ParserError!*ASTNode.Statement {
        _ = try this.expect(.LeftCurl);
        var first: ?*ASTNode.Statement = null;
        var last: ?*ASTNode.Statement = null;
        while (this.hasNext() and this.peek().id != .RightCurl) {
            const node = try this.parseStatement();
            const stmt = try this.createNode(ASTNode.Statement, .{ .payload = node, .next = null });
            if (last) |l| {
                l.next = stmt;
            } else {
                first = stmt;
            }
            last = stmt;
        }
        _ = try this.expect(.RightCurl);
        return first orelse try this.createNode(ASTNode.Statement, .{ .payload = try this.newNode(.undefined), .next = null });
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
                std.debug.print("Unexpected token in parseInfix: {s}\n", .{@tagName(tok.id)});
                return error.UnexpectedToken;
            },
        };
    }
};

    fn parseNode(node: *const ASTNode, prefix: []const u8, is_last: bool) void {
        _ = prefix;
        _ = is_last;
        std.debug.print("Node({s})\n", .{@tagName(node.*)});
    }
    
fn printStatementList(first: *const ASTNode.Statement, prefix: []const u8, is_last: bool) void {
        var curr: ?*const ASTNode.Statement = first;
        const new_prefix = nextPrefix(prefix, is_last);
        while (curr) |s| {
            printNode(s.payload, new_prefix, s.next == null);
            curr = s.next;
        }
    }

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
                    std.debug.print("├─ Param({s})\n", .{ p.name.lexme });
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

    fn printStatementList(first: *const ASTNode.Statement, prefix: []const u8, is_last: bool) void {
        var curr: ?*const ASTNode.Statement = first;
        const new_prefix = nextPrefix(prefix, is_last);
        while (curr) |s| {
            parseNode(s.payload, new_prefix, s.next == null);
            curr = s.next;
        }
    }

    fn printNode(node: *const ASTNode, prefix: []const u8, is_last: bool) void {
        parseNode(node, prefix, is_last);
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

test "parser basic expression" {
    const src = lexer.Source.make("test", "1 * (2 + 199);");
    var parser = try Parser.init(std.testing.allocator, src);
    defer {
        parser.allocator.deinit();
        // Since createNode uses baseAllocator, we don't have a way to easily free those 
        // without keeping track or using a better allocator.
        // For tests, this might leak unless we use an arena.
    }
    const tree = try parser.parse();
    try std.testing.expect(tree.* == .statement);
}

test "parser complex code" {
    const code = 
        \\const x: i32 = 5;
        \\fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
        \\var y = add(x, 10);
    ;
    const src = lexer.Source.make("test", code);
    var parser = try Parser.init(std.testing.allocator, src);
    defer parser.allocator.deinit();
    const tree = try parser.parse();
    try std.testing.expect(tree.* == .statement);
}
