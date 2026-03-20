const std = @import("std");
const lexer = @import("ziglt/lexer.zig");
const parse = @import("ziglt/parse.zig");

pub const Parser = parse.Parser;
pub const AstNode = parse.ASTNode;
pub const printAST = parse.printAST;
pub const Source = lexer.Source;

test "ziglt tests" {
    std.testing.refAllDecls(lexer);
    std.testing.refAllDecls(parse);
}

// TODO: finish parser
// TODO: Refactor alloctor to be a dynamicly-sized arena allocator
// TODO: test parser
// TODO: refactor parser to be a table based approach
// TODO: fully design initial draft of ziglt
// TODO: statements + expressions
// TODO: bytecode design
// TODO: vm implementation
// TODO: bytecode emissions
// TODO: optimizations (pin-hole+macro-opcodes, pruning, constant folding + propogation)
// TODO: Comptime evaluation
// TODO: jit backend
