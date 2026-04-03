const std = @import("std");

pub fn LinkedList(comptime T: type) type {
    return struct {
        const This = @This();

        const Node = struct {
            value: T,
            next: ?*Node,
        };

        allocator: std.mem.Allocator,
        root: ?*Node,
        head: ?*Node,
        count: usize,

        pub fn init(arena: std.mem.allocator) This {
            return .{
                .allocator = arena,
                .root = null,
                .head = null,
                .count = 0,
            };
        }

        pub fn append(this: *This, value: T) !void {
            const newNode = try this.allocator.create(Node);
            errdefer this.allocator.free(newNode);

            newNode.* = .{ .value = value, .next = null };

            if (this.root == null) {
                std.debug.assert(this.head == null);
                std.debug.assert(this.count == 0);

                this.root = newNode;
                this.head = newNode;
                this.count += 1;
                return;
            }

            this.head.?.next = newNode;
            this.head = newNode;
            this.count += 1;
        }

        pub fn items(this: *This) Iter {
            return .{ .node = this.root };
        }

        pub const Iter = struct {
            node: ?*Node,

            pub fn next(this: *@This()) ?T {
                if (this.node) |node| {
                    const value = node.value;
                    this.node = node.next;
                    return value;
                }

                return null;
            }
        };
    };
}
