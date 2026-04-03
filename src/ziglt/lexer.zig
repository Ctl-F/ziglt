const std = @import("std");
const parser = @import("parse.zig");

const ParseError = parser.ParserError;

pub const TokenID = enum {
    Invalid,
    Eof,

    // Keywords
    And,
    Break,
    Catch,
    Const,
    Continue,
    Comptime,
    Defer,
    Else,
    Enum,
    Error,
    Errdefer,
    False,
    For,
    Fn,
    If,
    Import,
    ImmediateChar,
    ImmediateFloat,
    ImmediateInteger,
    ImmediateString,
    Or,
    Orelse,
    Pub,
    Return,
    Struct,
    Switch,
    True,
    Try,
    Undefined,
    Unreachable,
    Union,
    Var,
    While,

    // Literals & identifiers
    Identifier,
    Comment,
    Annotation, // for runtime reflection purposes (future feature)
    Whitespace, // discarded

    // Operators
    Amp, // &
    AmpEq, // &=
    Asterisk, // *
    AsteriskAsterisk, // **
    AsteriskEq, // *=
    Bang, // !
    Caret, // ^
    CaretEq, // ^=
    Colon, // :
    Comma, // ,
    DoubleEqual, // ==
    Equal, // =
    ForwardSlash, // /
    ForwardSlEq, // /=
    GreaterEqual, // >=
    Greater, // >
    GreaterGreater, // >>
    GreaterGreaterEq, // >>=
    Less, // <
    LessEqual, // <=
    LessLess, // <<,
    LessLessEq, // <<=,
    LeftBracket, // [
    LeftCurl, // {
    LeftParen, // (
    Minus, // -
    MinusEq, // -=
    NotEqual, // !=
    Period, // .
    PeriodRange, // ..
    PeriodAst, // .*
    PeriodQuest, // .?
    Percent, // %
    PercentEq, // %=
    Pipe, // |
    PipeEq, // |=
    Plus, // +
    PlusEq, // +=
    Question, // ?
    RightBracket, // ]
    RightCurl, // }
    RightParen, // )
    Semicolon, // ;
    Tilde, // ~
    TildeEq, // ~=
    BackSlash, // \
    At, // @
};

pub const Token = struct {
    id: TokenID,
    start: u32,
    len: u32,
    sourceID: u16 = 0xFFFF,

    pub const Error = @This(){ .id = .Invalid, .start = 0, .len = 0 };
    pub const Eof = @This(){ .id = .Eof, .start = std.math.maxInt(u32), .len = std.math.maxInt(u32) };
};

pub const Source = struct {
    name: []const u8,
    original: []const u8, // copy of the original slice
    input: []const u8, // rolling view of source (this will shrink with each token consumed)
    consumed: u32, // total characters already consumed

    pub fn make(name: []const u8, source: []const u8) @This() {
        if (source.len > @as(usize, @intCast(std.math.maxInt(u32)))) {
            unreachable;
        }

        return @This(){
            .name = name,
            .original = source,
            .input = source,
            .consumed = 0,
        };
    }

    pub fn getPosition(this: @This(), token: Token) struct { col: u32, line: u32 } {
        var col: u32 = 0;
        var line: u32 = 0;
        var index = token.start;

        while (index > 0) : (index -= 1) {
            if (this.original[index] == '\n') {
                line += 1;
                continue;
            }

            if (line == 0) {
                // measuring column still
                col += 1;
            }
        }

        return .{ .col = col, .line = line };
    }

    pub fn getLexme(this: @This(), token: Token) []const u8 {
        if (token.id == .Eof) return "<EOF>";
        if (token.id == .Invalid) return "<ERR>";

        const start: usize = @intCast(token.start);
        const end = start + @as(usize, @intCast(token.len));

        return this.original[start..end];
    }

    pub fn reportError(this: @This(), err: ParseError, token: Token, expected: ?TokenID) ParseError!*parser.ASTNode {
        const position = this.getPosition(token);

        std.debug.print("Error found on line {}, col {}\n", .{ position.line, position.col });

        const line = blk: {
            var i = token.start;
            while (i > 0) : (i -= 1) {
                if (this.original[i] == '\n') break;
            }
            break :blk this.original[i .. token.start + token.len];
        };

        std.debug.print("{s}\n", .{line});

        var count = line.len - token.len;
        while (count > 0) : (count -= 1) {
            std.debug.print(" ", .{});
        }
        while (count < token.len) : (count += 1) {
            std.debug.print("~", .{});
        }
        std.debug.print("\n", .{});

        if (expected) |expect| {
            std.debug.print("Expected: {}\n", .{expect});
        }

        return err;
    }
};

pub fn tokenize(src: *Source, sourceID: u16) Token {
    if (src.input.len == 0) return Token.Eof;

    if (tokenizeWhitespace(src)) |_| {
        if (src.input.len == 0) return Token.Eof;
    }

    const first = src.input[0];

    const len = src.input.len;

    var token = switch (first) {
        'A'...'Z', 'a'...'z', '_' => tokenizeIdentifier(src),
        '0'...'9' => tokenizeNumber(src),
        '/' => tokenizeCommentOrOperator(src),
        '"' => tokenizeString(src),
        '\'' => tokenizeChar(src),
        else => tokenizeOperator(src),
    };

    std.debug.assert(src.input.len < len);

    token.sourceID = sourceID;

    return token;
}

const TokenPattern = struct {
    lexme: []const u8,
    result: TokenID,
    ignoreMe: bool = false,
};
const Keywords = [_]TokenPattern{
    .{ .lexme = "and", .result = .And },
    .{ .lexme = "break", .result = .Break },
    .{ .lexme = "catch", .result = .Catch },
    .{ .lexme = "const", .result = .Const },
    .{ .lexme = "continue", .result = .Continue },
    .{ .lexme = "comptime", .result = .Comptime },
    .{ .lexme = "defer", .result = .Defer },
    .{ .lexme = "else", .result = .Else },
    .{ .lexme = "enum", .result = .Enum },
    .{ .lexme = "errdefer", .result = .Errdefer },
    .{ .lexme = "false", .result = .False },
    .{ .lexme = "for", .result = .For },
    .{ .lexme = "fn", .result = .Fn },
    .{ .lexme = "if", .result = .If },
    .{ .lexme = "import", .result = .Import },
    .{ .lexme = "or", .result = .Or },
    .{ .lexme = "orelse", .result = .Orelse },
    .{ .lexme = "pub", .result = .Pub },
    .{ .lexme = "return", .result = .Return },
    .{ .lexme = "struct", .result = .Struct },
    .{ .lexme = "switch", .result = .Switch },
    .{ .lexme = "true", .result = .True },
    .{ .lexme = "try", .result = .Try },
    .{ .lexme = "undefined", .result = .Undefined },
    .{ .lexme = "unreachable", .result = .Unreachable },
    .{ .lexme = "union", .result = .Union },
    .{ .lexme = "var", .result = .Var },
    .{ .lexme = "while", .result = .While },
};
fn maxKeywordLength() u32 {
    var len: u32 = 0;
    inline for (Keywords) |kw| {
        len = @max(len, kw.lexme.len);
    }
    return len;
}
const BUCKET_COUNT = maxKeywordLength() + 1;
const BUCKET_SIZE = Keywords.len; // overkill, but should be fine for now
fn genBuckets() [BUCKET_COUNT][BUCKET_SIZE]TokenPattern {
    const bucket = [_]TokenPattern{.{ .ignoreMe = true, .lexme = "", .result = .Invalid }} ** BUCKET_SIZE;
    var buckets = [_][BUCKET_SIZE]TokenPattern{bucket} ** BUCKET_COUNT;

    inline for (Keywords) |keyword| {
        comptime {
            std.debug.assert(keyword.lexme.len < BUCKET_COUNT);
        }
        INDEX_SCAN: for (&buckets[keyword.lexme.len]) |*slot| {
            if (slot.ignoreMe) {
                slot.* = keyword;
                break :INDEX_SCAN;
            }
        } else {
            // this should never happen since each bucket should be large enough to theoretically hold every keyword
            @compileError("Too many keywords for the bucket. Current keyword is: " ++ keyword.lexme);
        }
    }

    return buckets;
}

const KeywordBuckets = genBuckets();

fn findKeyword(src: *Source, len: u32) TokenID {
    if (len > maxKeywordLength()) return .Invalid;

    const bucket = KeywordBuckets[len];

    for (bucket) |keyword| {
        if (keyword.ignoreMe) {
            break; // we reached the end of defined keywords in the bucket
        }
        if (std.mem.eql(u8, keyword.lexme, src.input[0..len])) {
            return keyword.result;
        }
    }

    return .Invalid;
}

// ALL OF THE tokenize* Expect SRC to not be at EOF (as guarenteed by the public tokenize function)
// E.G. all inputs for tokenize* will have src.input be at least length 1

fn tokenizeIdentifier(src: *Source) Token {
    var extra: u32 = 0;
    var index: usize = 1;

    GREEDY: while (index < src.input.len) : (index += 1) {
        switch (src.input[index]) {
            'A'...'Z', 'a'...'z', '_', '0'...'9' => {
                extra += 1;
            },
            else => break :GREEDY,
        }
    }
    // +1 since we've already matched the first identifier char
    // just by being here in the function
    const totalLength = extra + 1;
    defer consume(src, totalLength);

    const kwId = findKeyword(src, totalLength);

    if (kwId == .Invalid) {
        return createToken(src, totalLength, .Identifier);
    }
    return createToken(src, totalLength, kwId);
}

// TODO: Add HEX and BIN syntax
fn tokenizeNumber(src: *Source) Token {
    var extra: u32 = 0;
    var hasDecimal: bool = false;

    GREEDY: for (1..src.input.len) |index| {
        switch (src.input[index]) {
            '.' => {
                if (!hasDecimal) {
                    extra += 1;
                    hasDecimal = true;
                } else {
                    break :GREEDY;
                }
            },
            '0'...'9' => {
                extra += 1;
            },
            else => break :GREEDY,
        }
    }

    // if the termination char is a '.' we don't want it to be part of the number
    if (src.input[extra] == '.') {
        extra -= 1;
        hasDecimal = false;
    }

    const totalLength = extra + 1;
    defer consume(src, totalLength);

    return createToken(src, totalLength, if (hasDecimal) .ImmediateFloat else .ImmediateInteger);
}

inline fn tokenizeCommentOrOperator(src: *Source) Token {
    if (src.input.len == 1) return tokenizeOperator(src);

    return switch (src.input[1]) {
        '/' => tokenizeComment(src),
        else => tokenizeOperator(src),
    };
}

fn tokenizeComment(src: *Source) Token {
    // this is guarenteed to have at least '//' in src.input (as guarenteed by tokenizeCommentOrOperator)
    var blobLen: usize = 2;
    for (2..src.input.len) |idx| {
        if (src.input[idx] == '\n') break;
        blobLen += 1;
    }
    defer consume(src, @truncate(blobLen));
    return createToken(src, @truncate(blobLen), .Comment);
}

fn tokenizeDelimitedSpan(comptime delimiter: u8, comptime successID: TokenID, comptime errorID: TokenID, src: *Source) Token {
    var broken: bool = false;
    var extra: u32 = 0;

    GREEDY: for (1..src.input.len) |idx| {
        if (broken) {
            broken = false;
            extra += 1;
            continue;
        }
        switch (src.input[idx]) {
            delimiter => {
                extra += 1;
                break :GREEDY;
            },
            '\\' => {
                broken = true;
                extra += 1;
            },
            '\n' => {
                consume(src, 1);
                return Token{ .id = errorID, .len = 0, .start = src.consumed };
            },
            else => extra += 1,
        }
    } else {
        return Token{ .id = errorID, .len = 0, .start = src.consumed };
    }

    const totalLength = 1 + extra;
    defer consume(src, totalLength);

    return createToken(src, totalLength, successID);
}

/// returns Invalid if the string is not properly terminated
fn tokenizeString(src: *Source) Token {
    return tokenizeDelimitedSpan('"', .ImmediateString, .Invalid, src);
}

fn countCharSpan(span: []const u8) u32 {
    var count: u32 = 0;
    var idx: usize = 0;

    while (idx < span.len) : (idx += 1) {
        if (span[idx] == '\\') {
            if (idx + 1 >= span.len) {
                // I don't think this should be possible since I'm fairly sure
                // that tokenizeDelmitedSpan enforces correct escape sequence logic
                // in that every backslash should have at least one follow char unless
                // it itself is the following char.
                // this unreachable should help us find out for sure.
                unreachable;
            }
            idx += 1;
        }
        count += 1;
    }

    return count;
}

fn tokenizeChar(src: *Source) Token {
    const originalSlice = src.input;
    const token = tokenizeDelimitedSpan('\'', .ImmediateChar, .Invalid, src);

    if (countCharSpan(originalSlice[1 .. token.len - 1]) != 1) {
        return Token.Error;
    }

    return token;
}

fn tokenizeWhitespace(src: *Source) ?Token {
    var count: usize = 0;

    GREEDY: while (count < src.input.len) : (count += 1) {
        switch (src.input[count]) {
            ' ', '\t', '\r', '\n' => continue,
            else => break :GREEDY,
        }
    }

    if (count == 0) return null; // not truly an error, but also not a whitespace result
    defer consume(src, @truncate(count));
    return createToken(src, @truncate(count), .Whitespace);
}

fn matchOperator(src: *Source, comptime options: []const TokenPattern) ?struct { id: TokenID, len: usize } {
    inline for (options) |pattern| {
        if (src.input.len >= pattern.lexme.len and std.mem.eql(u8, pattern.lexme, src.input[0..pattern.lexme.len])) return .{
            .id = pattern.result,
            .len = pattern.lexme.len,
        };
    }
    return null;
}

fn tokenizeOperator(src: *Source) Token {
    const id: TokenID, const len: usize = switch (src.input[0]) {
        '&' => A: {
            const result = matchOperator(src, &.{
                .{ .lexme = "&=", .result = .AmpEq },
                .{ .lexme = "&", .result = .Amp },
            }) orelse unreachable;
            break :A .{ result.id, result.len };
        },
        '*' => B: {
            const result = matchOperator(src, &.{
                .{ .lexme = "*=", .result = .AsteriskEq },
                .{ .lexme = "**", .result = .AsteriskAsterisk },
                .{ .lexme = "*", .result = .Asterisk },
            }) orelse unreachable;
            break :B .{ result.id, result.len };
        },
        '!' => C: {
            const result = matchOperator(src, &.{
                .{ .lexme = "!=", .result = .NotEqual },
                .{ .lexme = "!", .result = .Bang },
            }) orelse unreachable;
            break :C .{ result.id, result.len };
        },
        '^' => D: {
            const result = matchOperator(src, &.{
                .{ .lexme = "^=", .result = .CaretEq },
                .{ .lexme = "^", .result = .Caret },
            }) orelse unreachable;
            break :D .{ result.id, result.len };
        },
        ':' => .{ .Colon, 1 },
        ',' => .{ .Comma, 1 },
        '=' => E: {
            const result = matchOperator(src, &.{
                .{ .lexme = "==", .result = .DoubleEqual },
                .{ .lexme = "=", .result = .Equal },
            }) orelse unreachable;
            break :E .{ result.id, result.len };
        },
        '/' => F: {
            const result = matchOperator(src, &.{
                .{ .lexme = "/=", .result = .ForwardSlEq },
                .{ .lexme = "/", .result = .ForwardSlash },
                // double forward slash should never happen since it's handled in commentOrOperator
            }) orelse unreachable;
            break :F .{ result.id, result.len };
        },
        '>' => G: {
            const result = matchOperator(src, &.{
                .{ .lexme = ">>=", .result = .GreaterGreaterEq },
                .{ .lexme = ">>", .result = .GreaterGreater },
                .{ .lexme = ">=", .result = .GreaterEqual },
                .{ .lexme = ">", .result = .Greater },
            }) orelse unreachable;
            break :G .{ result.id, result.len };
        },
        '<' => H: {
            const result = matchOperator(src, &.{
                .{ .lexme = "<<=", .result = .LessLessEq },
                .{ .lexme = "<<", .result = .LessLess },
                .{ .lexme = "<=", .result = .LessEqual },
                .{ .lexme = "<", .result = .Less },
            }) orelse unreachable;
            break :H .{ result.id, result.len };
        },
        '[' => .{ .LeftBracket, 1 },
        '{' => .{ .LeftCurl, 1 },
        '(' => .{ .LeftParen, 1 },
        '-' => I: {
            const result = matchOperator(src, &.{
                .{ .lexme = "-=", .result = .MinusEq },
                .{ .lexme = "-", .result = .Minus },
            }) orelse unreachable;
            break :I .{ result.id, result.len };
        },
        '.' => J: {
            const result = matchOperator(src, &.{
                .{ .lexme = "..", .result = .PeriodRange },
                .{ .lexme = ".*", .result = .PeriodAst },
                .{ .lexme = ".?", .result = .PeriodQuest },
                .{ .lexme = ".", .result = .Period },
            }) orelse unreachable;
            break :J .{ result.id, result.len };
        },
        '%' => K: {
            const result = matchOperator(src, &.{
                .{ .lexme = "%=", .result = .PercentEq },
                .{ .lexme = "%", .result = .Percent },
            }) orelse unreachable;
            break :K .{ result.id, result.len };
        },
        '|' => L: {
            const result = matchOperator(src, &.{
                .{ .lexme = "|=", .result = .PipeEq },
                .{ .lexme = "|", .result = .Pipe },
            }) orelse unreachable;
            break :L .{ result.id, result.len };
        },
        '+' => M: {
            const result = matchOperator(src, &.{
                .{ .lexme = "+=", .result = .PlusEq },
                .{ .lexme = "+", .result = .Plus },
            }) orelse unreachable;
            break :M .{ result.id, result.len };
        },
        '?' => .{ .Question, 1 },
        ']' => .{ .RightBracket, 1 },
        '}' => .{ .RightCurl, 1 },
        ')' => .{ .RightParen, 1 },
        ';' => .{ .Semicolon, 1 },
        '~' => N: {
            const result = matchOperator(src, &.{
                .{ .lexme = "~=", .result = .TildeEq },
                .{ .lexme = "~", .result = .Tilde },
            }) orelse unreachable;
            break :N .{ result.id, result.len };
        },
        '\\' => .{ .BackSlash, 1 },
        '@' => .{ .At, 1 },
        else => {
            consume(src, 1);
            return Token.Error;
        },
    };
    defer consume(src, @truncate(len));
    return createToken(src, @truncate(len), id);
}

fn createToken(src: *Source, len: u32, id: TokenID) Token {
    return Token{
        .id = id,
        .start = src.consumed,
        .len = len,
        .sourceID = 0xFFFF,
    };
}

fn consume(src: *Source, len: u32) void {
    src.consumed += len;
    src.input = src.input[len..];
}

fn makeSource(input: []const u8) Source {
    return .{
        .name = "test",
        .original = input,
        .input = input,
        .consumed = 0,
    };
}

fn expectToken(tok: Token, id: TokenID, start: u32, len: u32) !void {
    try std.testing.expectEqual(id, tok.id);
    try std.testing.expectEqual(start, tok.start);
    try std.testing.expectEqual(len, tok.len);
}

test "tokenizeWhitespace basic" {
    var src = makeSource("   abc");

    const tok = tokenizeWhitespace(&src) orelse unreachable;

    try expectToken(tok, .Whitespace, 0, 3);
    try std.testing.expectEqualStrings("abc", src.input);
}

test "tokenizeWhitespace newline tab" {
    var src = makeSource("\n\t test");

    const tok = tokenizeWhitespace(&src) orelse unreachable;

    try expectToken(tok, .Whitespace, 0, 3);
}

test "tokenizeWhitespace none" {
    var src = makeSource("abc");

    const tok = tokenizeWhitespace(&src);

    try std.testing.expect(tok == null);
}

test "tokenizeIdentifier simple" {
    var src = makeSource("hello");

    const tok = tokenizeIdentifier(&src);

    try expectToken(tok, .Identifier, 0, 5);
}

test "tokenizeIdentifier with numbers" {
    var src = makeSource("abc123");

    const tok = tokenizeIdentifier(&src);

    try expectToken(tok, .Identifier, 0, 6);
}

test "tokenizeIdentifier keyword" {
    var src = makeSource("return");

    const tok = tokenizeIdentifier(&src);

    try expectToken(tok, .Return, 0, 6);
}

test "tokenizeIdentifier keyword prefix" {
    var src = makeSource("returning");

    const tok = tokenizeIdentifier(&src);

    try expectToken(tok, .Identifier, 0, 9);
}

test "tokenizeNumber integer" {
    var src = makeSource("12345");

    const tok = tokenizeNumber(&src);

    try expectToken(tok, .ImmediateInteger, 0, 5);
}

test "tokenizeNumber float" {
    var src = makeSource("123.45");

    const tok = tokenizeNumber(&src);

    try expectToken(tok, .ImmediateFloat, 0, 6);
}

test "tokenizeNumber int exclude trailing dot" {
    var src = makeSource("1.");

    const tok = tokenizeNumber(&src);

    try expectToken(tok, .ImmediateInteger, 0, 1);

    const tok2 = tokenizeOperator(&src);

    try std.testing.expectEqual(tok2.id, .Period);
}

test "tokenizeNumber stop second decimal" {
    var src = makeSource("1.2.3");

    const tok = tokenizeNumber(&src);

    try expectToken(tok, .ImmediateFloat, 0, 3);
}

test "tokenizeComment basic" {
    var src = makeSource("// hello\nx");

    const tok = tokenizeComment(&src);

    try expectToken(tok, .Comment, 0, 8);
}

test "tokenizeComment eof" {
    var src = makeSource("// hello");

    const tok = tokenizeComment(&src);

    try expectToken(tok, .Comment, 0, 8);
}

test "tokenizeString basic" {
    var src = makeSource("\"hello\"");

    const tok = tokenizeString(&src);

    try expectToken(tok, .ImmediateString, 0, 7);
}

test "tokenizeString escaped quote" {
    var src = makeSource("\"he\\\"llo\"");

    const tok = tokenizeString(&src);

    try std.testing.expectEqual(.ImmediateString, tok.id);
}

test "tokenizeString unterminated" {
    var src = makeSource("\"hello");

    const tok = tokenizeString(&src);

    try std.testing.expectEqual(.Invalid, tok.id);
}

test "tokenizeChar basic" {
    var src = makeSource("'a'");

    const tok = tokenizeChar(&src);

    try expectToken(tok, .ImmediateChar, 0, 3);
}

test "tokenizeChar escaped" {
    var src = makeSource("'\\n'");

    const tok = tokenizeChar(&src);

    try std.testing.expectEqual(.ImmediateChar, tok.id);
}

test "tokenizeChar too many" {
    var src = makeSource("'ab'");

    const tok = tokenizeChar(&src);

    try std.testing.expectEqual(.Invalid, tok.id);
}

test "tokenizeOperator plus" {
    var src = makeSource("+");

    const tok = tokenizeOperator(&src);

    try expectToken(tok, .Plus, 0, 1);
}

test "tokenizeOperator plus equals" {
    var src = makeSource("+=");

    const tok = tokenizeOperator(&src);

    try expectToken(tok, .PlusEq, 0, 2);
}

test "tokenizeOperator shift" {
    var src = makeSource(">>");

    const tok = tokenizeOperator(&src);

    try expectToken(tok, .GreaterGreater, 0, 2);
}

test "tokenizeOperator shift equals" {
    var src = makeSource(">>=");

    const tok = tokenizeOperator(&src);

    try expectToken(tok, .GreaterGreaterEq, 0, 3);
}

test "tokenizeCommentOrOperator comment" {
    var src = makeSource("//test");

    const tok = tokenizeCommentOrOperator(&src);

    try std.testing.expectEqual(.Comment, tok.id);
}

test "tokenizeCommentOrOperator slash operator" {
    var src = makeSource("/=");

    const tok = tokenizeCommentOrOperator(&src);

    try expectToken(tok, .ForwardSlEq, 0, 2);
}

test "tokenize full expression" {
    var src = makeSource("var x = 5;");

    try std.testing.expectEqual(.Var, tokenize(&src).id);
    try std.testing.expectEqual(.Identifier, tokenize(&src).id);
    try std.testing.expectEqual(.Equal, tokenize(&src).id);
    try std.testing.expectEqual(.ImmediateInteger, tokenize(&src).id);
    try std.testing.expectEqual(.Semicolon, tokenize(&src).id);
}

test "tokenize math expression" {
    var src = makeSource("1 + 2 * 3");

    try std.testing.expectEqual(.ImmediateInteger, tokenize(&src).id);
    try std.testing.expectEqual(.Plus, tokenize(&src).id);
    try std.testing.expectEqual(.ImmediateInteger, tokenize(&src).id);
    try std.testing.expectEqual(.Asterisk, tokenize(&src).id);
    try std.testing.expectEqual(.ImmediateInteger, tokenize(&src).id);
}

test "tokenize entire file until EOF" {
    var src = makeSource("var x = 10 + 20;");

    while (true) {
        const tok = tokenize(&src);
        if (tok.id == .Eof) break;
    }

    try std.testing.expect(src.input.len == 0);
}

test "tokenize empty input" {
    var src = makeSource("");

    const tok = tokenize(&src);

    try std.testing.expectEqual(.Eof, tok.id);
}

test "tokenize only whitespace" {
    var src = makeSource("   \n\t");

    const tok = tokenize(&src);

    try std.testing.expectEqual(.Eof, tok.id);
}

test "operator longest match precedence" {
    var src = makeSource(">>= >> >");

    try std.testing.expectEqual(.GreaterGreaterEq, tokenize(&src).id);
    try std.testing.expectEqual(.GreaterGreater, tokenize(&src).id);
    try std.testing.expectEqual(.Greater, tokenize(&src).id);
}

test "identifier underscore" {
    var src = makeSource("_");

    const tok = tokenizeIdentifier(&src);

    try expectToken(tok, .Identifier, 0, 1);
}

test "identifier underscore prefix" {
    var src = makeSource("_abc123");

    const tok = tokenizeIdentifier(&src);

    try expectToken(tok, .Identifier, 0, 7);
}

test "keyword followed by identifier char" {
    var src = makeSource("return1");

    const tok = tokenizeIdentifier(&src);

    try expectToken(tok, .Identifier, 0, 7);
}

test "dot number form" {
    var src = makeSource(".5");

    try std.testing.expectEqual(.Period, tokenize(&src).id);
    try std.testing.expectEqual(.ImmediateInteger, tokenize(&src).id);
}

test "range operator vs float" {
    var src = makeSource("1..2");

    try std.testing.expectEqual(.ImmediateInteger, tokenize(&src).id);
    try std.testing.expectEqual(.PeriodRange, tokenize(&src).id);
    try std.testing.expectEqual(.ImmediateInteger, tokenize(&src).id);
}

test "string escaped backslash" {
    var src = makeSource("\"\\\\\"");

    const tok = tokenizeString(&src);

    try std.testing.expectEqual(.ImmediateString, tok.id);
}

test "string escape at EOF" {
    var src = makeSource("\"abc\\");

    const tok = tokenizeString(&src);

    try std.testing.expectEqual(.Invalid, tok.id);
}

test "invalid character" {
    var src = makeSource("`");

    const tok = tokenize(&src);

    try std.testing.expectEqual(.Invalid, tok.id);
}
