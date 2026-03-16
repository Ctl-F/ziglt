const std = @import("std");
const lexer = @import("ziglt/lexer.zig");

test "ziglt tests" {
    std.testing.refAllDecls(lexer);
}
