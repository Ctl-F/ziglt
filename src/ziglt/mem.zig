const std = @import("std");

pub const ArenaConfig = struct {
    BlockSize: usize = 512,
};

pub const ArenaAllocatorError = error{
    OutOfMemory,
};

pub fn ArenaAllocator(comptime ObjectType: type, comptime config: ArenaConfig) type {
    return struct {
        const This = @This();
        const Block = struct {
            buffer: [config.BlockSize]ObjectType,
            head: usize,
            nextBlock: ?*Block,

            fn next(this: *@This()) ?*ObjectType {
                if (this.isFull()) return null;
                defer this.head += 1;
                return &this.buffer[this.head];
            }

            inline fn pop(this: *@This()) void {
                this.head -= 1;
            }

            inline fn isFull(this: *@This()) bool {
                return this.head >= this.buffer.len;
            }

            inline fn items(this: *@This()) []ObjectType {
                return this.buffer[0..this.head];
            }
        };

        root: ?*Block,
        head: ?*Block,
        parent: std.mem.Allocator,

        pub fn init(parent: std.mem.Allocator) This {
            return .{
                .parent = parent,
                .root = null,
                .head = null,
            };
        }

        pub fn create(this: *This) !*ObjectType {
            var headBlock = try this.getHead();

            // getHead should handle the case where the block is already full
            // so next should not fail
            const ptr = headBlock.next().?;

            return ptr;
        }

        pub const ItemsIterator = struct {
            blocks: BlockIterator,
            currentBlock: ?*Block,
            cursor: usize,

            pub fn next(this: *@This()) ?*ObjectType {
                if (this.currentBlock == null) {
                    this.moveNextBlock();
                    if (this.currentBlock == null) return null;
                }

                if (this.currentBlock) |block| {
                    if (this.isAtEndOfBlock(block)) {
                        this.moveNextBlock();
                        return this.next();
                    }

                    defer this.cursor += 1;
                    return &block.items[this.cursor];
                } else unreachable;
            }

            fn moveNextBlock(this: *@This()) void {
                this.currentBlock = this.blocks.next();
                this.cursor = 0;
            }

            inline fn isAtEndOfBlock(this: *@This(), block: *Block) bool {
                return this.cursor >= block.head;
            }
        };

        pub const BlockIterator = struct {
            head: ?*Block,

            pub fn next(this: *@This()) ?*Block {
                defer if (&this.head) |*head| {
                    head.* = head.nextBlock;
                };

                return this.head;
            }
        };

        pub fn resetKeepCapacity(this: *This()) void {
            var iter = BlockIterator{
                .head = this.root,
            };
            while (iter.next()) |block| {
                block.head = 0;
            }
            this.head = this.root;
        }

        pub fn deinit(this: *This()) void {
            var iter = BlockIterator{
                .head = this.root,
            };
            while (iter.next()) |block| {
                this.parent.free(block);
            }
        }

        fn getHead(this: *This) !*Block {
            if (this.head) |head| {
                if (!head.isFull()) return head;
            }
            return try this.makeBlock();
        }

        fn makeBlock(this: *This) ArenaAllocatorError!*Block {
            const block = this.parent.create(Block) catch return error.OutOfMemory;
            errdefer this.parent.free(block);

            if (this.root == null) {
                this.root = block;
                this.head = block;
                return block;
            }

            if (this.head == null) unreachable;

            this.head.?.nextBlock = block;
            this.head = this.head.?.nextBlock;
            return block;
        }
    };
}

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
