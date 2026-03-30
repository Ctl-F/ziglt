const std = @import("std");
const ziglt = @import("ziglt");

pub fn main() !void {
    var allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer allocator.deinit();
    const alloc = allocator.allocator();

    const src = ziglt.Source.make("Testing", "1 + 2 * (3 - 5 << 6 & foo[bar])");

    var parser = try ziglt.Parser.init(alloc, src);

    const tree = try parser.parseExpression(.Lowest);
    ziglt.printAST(tree);
}

const testSource = @embedFile("testing.zlt");
