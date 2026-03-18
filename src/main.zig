const std = @import("std");
const ziglt = @import("ziglt");

pub fn main() !void {
    var allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer allocator.deinit();
    const alloc = allocator.allocator();

    const src = ziglt.Source.make("Testing", "1 * (2 + 199)");

    var parser = try ziglt.Parser.init(alloc, src);

    const tree = try parser.parse();
    ziglt.printAST(tree);
}
