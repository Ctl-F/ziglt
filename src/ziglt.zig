const std = @import("std");
const lexer = @import("ziglt/lexer.zig");
const parse = @import("ziglt/parse.zig");

pub const Parser = parse.Parser;
pub const AstNode = parse.ASTNode;
pub const printAST = parse.printAST;
pub const Source = lexer.Source;

test "ziglt tests" {
    std.testing.refAllDecls(lexer);
}

// TODO: Debug parser+AST to figure out why it's complaining on allocator free
// TODO: Implement custom slab allocator rather than using arena allocator
//      this might fix the issue.
// TODO: test parser
// TODO: refactor parser to be a table based approach
// TODO: fully design initial draft of ziglt
// TODO: statements + expressions
// TODO: bytecode design
// TODO: vm implementation
// TODO: bytecode emissions
// TODO: optimizations
// TODO: jit backend
