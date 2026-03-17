const std = @import("std");
const lexer = @import("lexer.zig");
const bytecode = @import("bytecode.zig");

const Token = lexer.Token;

pub const BinaryOp = enum {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
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
    Lowest,
    Sum,
    Product,
    Prefix,
};

pub const ParserError = error{
    AllocationError,
};

pub const Parser = struct {
    const This = @This();

    allocator: std.mem.Allocator,
    source: lexer.Source,
    window: [2]Token = [_]Token{ Token.Eof, Token.Eof },

    pub fn init(allocator: std.mem.Allocator, source: lexer.Source) This {
        var inst = This{ .allocator = allocator, .source = source };
        inst.window[0] = lexer.tokenize(&inst.source);
        inst.window[1] = lexer.tokenize(&inst.source);
        return inst;
    }

    fn peek(this: *This) Token {
        return this.window[1];
    }

    fn next(this: *This) Token {
        const token = this.window[0];
        this.window[0] = this.window[1];
        this.window[1] = lexer.tokenize(&this.source);
        return token;
    }

    fn hasNext(this: *This) bool {
        return this.peek().id != .Eof;
    }

    fn newNode(this: *This, node: ASTNode) ParserError!*ASTNode {
        const ptr = this.allocator.create(ASTNode) catch return error.AllocationError;
        ptr.* = node;
        return ptr;
    }

    fn getPrec(id: lexer.TokenID) Precedence {
        return switch (id) {
            .Plus, .Minus => .Sum,
            .Asterisk, .ForwardSlash, .Percent => .Product,
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
    //const stdout = std.Io.getStdOut().writer();
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch unreachable;

    // branch drawing
    if (prefix.len > 0) {
        stdout.print("{s}", .{prefix}) catch unreachable;
        stdout.print("{s}", .{if (is_last) "└─ " else "├─ "}) catch unreachable;
    }

    switch (node.*) {
        .immediate => |imm| {
            switch (imm) {
                .uint => |v| stdout.print("Int({d})\n", .{v}) catch unreachable,
                .float => |v| stdout.print("Float({})\n", .{v}) catch unreachable,
                .boolean => |v| stdout.print("Bool({})\n", .{v}) catch unreachable,
                .string => |v| stdout.print("String(\"{s}\")\n", .{v}) catch unreachable,
                .char => |v| stdout.print("Char({d})\n", .{v}) catch unreachable,
            }
        },

        .identifier => |ident| {
            stdout.print("Ident({s})\n", .{ident.lexme}) catch unreachable;
        },

        .unary => |u| {
            stdout.print("Unary({s})\n", .{unaryOpToString(u.op)}) catch unreachable;

            const new_prefix = nextPrefix(prefix, is_last);
            printNode(u.expr, new_prefix, true);
        },

        .binary => |b| {
            stdout.print("Binary({s})\n", .{binaryOpToString(b.op)}) catch unreachable;

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
