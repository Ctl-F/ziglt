const std = @import("std");

pub const SlabAllocatorConfig = struct {
    defaultObjectCapacity: usize = 512,
    defaultStackCapacity: usize = 128,
};

pub const SlabAllocatorError = error{
    ResizeError,
    Overflow,
    Underflow,
    OutOfMemory,
};

pub fn SlabAllocator(comptime ObjectType: type) type {
    return struct {
        const This = @This();

        baseAllocator: std.mem.Allocator,
        objects: BufferHead(ObjectType),
        freeStack: BufferHead(usize),

        pub fn init(parent: std.mem.Allocator, config: SlabAllocatorConfig) SlabAllocatorError!This {
            std.debug.assert(config.defaultObjectCapacity > 0);
            std.debug.assert(config.defaultStackCapacity > 0);

            const objectPool = try parent.alloc(ObjectType, config.defaultObjectCapacity);
            errdefer parent.free(objectPool);

            const freeStack = try parent.alloc(usize, config.defaultStackCapacity);
            errdefer parent.free(freeStack);

            return This{
                .baseAllocator = parent,
                .objects = .{ .buffer = objectPool, .head = 0 },
                .freeStack = .{ .buffer = freeStack, .head = 0 },
            };
        }

        pub fn deinit(this: *This) void {
            this.baseAllocator.free(this.objects.buffer);
            this.baseAllocator.free(this.freeStack.buffer);
        }

        fn BufferHead(comptime T: type) type {
            return struct {
                buffer: []T,
                head: usize,

                fn pop(this: *@This()) SlabAllocatorError!*T {
                    if (this.head == 0) return error.Underflow;

                    this.head -= 1;
                    return &this.buffer[this.head];
                }

                fn push(this: *@This(), obj: T) SlabAllocatorError!*T {
                    if (this.head >= this.buffer.len) return error.Overflow;

                    defer this.head += 1;
                    this.buffer[this.head] = obj;

                    return &this.buffer[this.head];
                }
            };
        }

        pub fn create(this: *This) SlabAllocatorError!*ObjectType {
            if (this.freeStack.head > 0) {
                const slot = this.freeStack.pop() catch unreachable;
                return &this.objects.buffer[slot.*];
            }

            return try this.objects.push(undefined);
        }

        pub fn free(this: *This, object: *ObjectType) void {
            if (this.findObject(object)) |slot| {
                _ = this.freeStack.push(slot) catch unreachable;
            }
        }

        fn findObject(this: *This, object: *ObjectType) ?usize {
            var cursor: usize = 0;
            while (cursor < this.objects.head) : (cursor += 1) {
                if (&this.objects.buffer[cursor] == object) break;
            } else {
                return null;
            }

            // is it already free
            var freeCursor: usize = 0;
            while (freeCursor < this.freeStack.head) : (freeCursor += 1) {
                // slot is already free
                if (this.freeStack.buffer[freeCursor] == cursor) return null;
            }

            return cursor;
        }
    };
}
