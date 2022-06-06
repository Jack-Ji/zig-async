const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        const Iterator = struct {
            target: *Self,

            direction: enum { forward, backward },
            index: usize,

            pub fn next(self: *Iterator) ?*T {
                if (self.index >= self.target.len()) return null;

                const real_index = if (self.direction == .forward) self.index else self.target.len() - 1 - self.index;
                if (self.target.get(real_index)) |item| {
                    self.index += 1;
                    return item;
                }

                return null;
            }
        };

        allocator: Allocator,

        buffer: []T = &[_]T{},

        head: usize = 0,
        tail: usize = 0,
        _len: usize = 0,

        /// Initialize a new buffer, no allocations are made until a `push*` method is called
        pub fn init(allocator: Allocator) Self {
            return .{ .allocator = allocator };
        }

        /// Initialize a new buffer that will be able to hold at least `num` items before allocating.
        pub fn initCapacity(allocator: Allocator, num: usize) !Self {
            var new = Self.init(allocator);
            try new.ensureTotalCapacityPrecise(num);
            return new;
        }

        /// Get the number of items that this buffer can hold before a reallocation is made.
        pub fn capacity(self: *const Self) usize {
            return self.buffer.len;
        }

        /// Get the numbers of items the buffer currently holds
        pub fn len(self: *const Self) usize {
            return self._len;
        }

        /// Reset without freeing memory
        pub fn clearRetainingCapacity(self: *Self) void {
            self._len = 0;
            self.head = 0;
            self.tail = 0;
        }

        /// Reset all internal fields and free the buffer.
        pub fn deinit(self: *Self) void {
            self.clearRetainingCapacity();

            if (self.capacity() > 0) {
                self.allocator.free(self.buffer);
                self.buffer.len = 0;
            }
        }

        /// Ensure the internal buffer can hold at least `needed` more elements, and reallocate if it can't.
        pub fn ensureUnusedCapacity(self: *Self, needed: usize) !void {
            return self.ensureTotalCapacity(self.capacity() + needed);
        }

        /// Grow the internal buffer to hold at least `target_capacity`
        pub fn ensureTotalCapacity(self: *Self, target_capacity: usize) !void {
            // Using the same algorithm for finding a better capacity as std.ArrayList (as of zig v0.9.0)
            if (target_capacity < self.capacity()) return;

            var better_capacity = self.capacity();
            while (true) {
                better_capacity += better_capacity / 2 + 8;
                if (better_capacity >= target_capacity) break;
            }

            return self.ensureTotalCapacityPrecise(better_capacity);
        }

        /// Grow the internal buffer to hold as close to `new_capacity` items as possible.
        /// It may hold more depending on the allocators realloc implementation
        pub fn ensureTotalCapacityPrecise(self: *Self, new_capacity: usize) !void {
            const old_capacity = self.capacity();
            if (old_capacity >= new_capacity) return;

            const new_buffer = try self.allocator.reallocAtLeast(self.buffer, new_capacity);
            self.buffer = new_buffer;

            // Nothing needs to be done
            if (self.tail < self.head) return;

            if (self.head <= old_capacity - self.tail) {
                // unwrap the head, moving after the tail
                if (self.head > 0)
                    std.mem.copy(T, self.buffer[old_capacity..], self.buffer[0..self.head]);

                self.head = old_capacity + self.head;
            } else {
                // shift the tail to the end of the array
                const new_tail = new_buffer.len - (old_capacity - self.tail);
                std.mem.copy(T, self.buffer[new_tail..], self.buffer[self.tail..old_capacity]);

                self.tail = new_tail;
            }
        }

        /// Add an item at the end of the buffer
        pub fn pushBack(self: *Self, item: T) !void {
            if (self.len() == self.capacity()) try self.ensureUnusedCapacity(1);

            self.buffer[self.head] = item;
            self.head = (self.head + 1) % self.capacity();
            self._len += 1;
        }

        /// Remove the last item in the buffer, or null if its empty
        pub fn popBack(self: *Self) ?T {
            if (self.len() == 0) return null;

            if (self.head == 0) self.head = self.capacity();
            self.head -= 1;
            self._len -= 1;

            return self.buffer[self.head];
        }

        /// Add an item at the start of the buffer
        pub fn pushFront(self: *Self, item: T) !void {
            if (self.len() == self.capacity()) try self.ensureUnusedCapacity(1);

            if (self.tail == 0) self.tail = self.capacity();
            self.tail -= 1;
            self._len += 1;

            self.buffer[self.tail] = item;
        }

        /// Remove the first item in the buffer, or null if its empty
        pub fn popFront(self: *Self) ?T {
            if (self.len() == 0) return null;

            const data = self.buffer[self.tail];

            self.tail = (self.tail + 1) % self.capacity();
            self._len -= 1;

            return data;
        }

        /// Get an item by index from the buffer
        pub fn get(self: *Self, i: usize) ?*T {
            if (i >= self.len()) return null;

            return &self.buffer[(self.tail + i) % self.capacity()];
        }

        /// Returns a new `Iterator` instance, for easy use with a while loop
        pub fn iter(self: *Self) Iterator {
            return .{
                .direction = .forward,

                .target = self,
                .index = 0,
            };
        }

        /// Same as `iter()` but iterates backwards from the end of a buffer
        pub fn iterReverse(self: *Self) Iterator {
            return .{
                .direction = .backward,

                .target = self,
                .index = 0,
            };
        }
    };
}

test "RingBuffer: pushBack / popBack" {
    {
        var ring = RingBuffer(u32).init(std.testing.allocator);
        defer ring.deinit();

        try std.testing.expectEqual(ring.len(), 0);
        try ring.pushBack(1);
        try std.testing.expectEqual(ring.len(), 1);
        try ring.pushBack(2);
        try std.testing.expectEqual(ring.len(), 2);
        try ring.pushBack(3);
        try std.testing.expectEqual(ring.len(), 3);
        try ring.pushBack(4);
        try std.testing.expectEqual(ring.len(), 4);

        try std.testing.expectEqual(ring.popBack(), 4);
        try std.testing.expectEqual(ring.len(), 3);

        try std.testing.expectEqual(ring.popBack(), 3);
        try std.testing.expectEqual(ring.len(), 2);

        try std.testing.expectEqual(ring.popBack(), 2);
        try std.testing.expectEqual(ring.len(), 1);

        try std.testing.expectEqual(ring.popBack(), 1);
        try std.testing.expectEqual(ring.len(), 0);

        try std.testing.expectEqual(ring.popBack(), null);
    }

    {
        var ring = RingBuffer(u32).init(std.testing.allocator);
        defer ring.deinit();

        try ring.pushBack(1);
        try std.testing.expectEqual(ring.len(), 1);
        try ring.pushBack(2);
        try std.testing.expectEqual(ring.len(), 2);
        try std.testing.expectEqual(ring.popBack(), 2);
        try std.testing.expectEqual(ring.len(), 1);

        try std.testing.expectEqual(ring.popBack(), 1);
        try std.testing.expectEqual(ring.len(), 0);

        try ring.pushBack(3);
        try std.testing.expectEqual(ring.len(), 1);
        try std.testing.expectEqual(ring.popBack(), 3);
        try std.testing.expectEqual(ring.len(), 0);

        try ring.pushBack(4);
        try std.testing.expectEqual(ring.len(), 1);
        try std.testing.expectEqual(ring.popBack(), 4);
        try std.testing.expectEqual(ring.len(), 0);

        try std.testing.expectEqual(ring.popBack(), null);
        try std.testing.expectEqual(ring.popBack(), null);
        try std.testing.expectEqual(ring.popBack(), null);
    }
}

test "RingBuffer: pushFront / popFront" {
    {
        var ring = RingBuffer(u32).init(std.testing.allocator);
        defer ring.deinit();

        try std.testing.expectEqual(ring.len(), 0);
        try ring.pushFront(1);
        try std.testing.expectEqual(ring.len(), 1);
        try ring.pushFront(2);
        try std.testing.expectEqual(ring.len(), 2);
        try ring.pushFront(3);
        try std.testing.expectEqual(ring.len(), 3);
        try ring.pushFront(4);
        try std.testing.expectEqual(ring.len(), 4);

        try std.testing.expectEqual(ring.popFront(), 4);
        try std.testing.expectEqual(ring.len(), 3);

        try std.testing.expectEqual(ring.popFront(), 3);
        try std.testing.expectEqual(ring.len(), 2);

        try std.testing.expectEqual(ring.popFront(), 2);
        try std.testing.expectEqual(ring.len(), 1);

        try std.testing.expectEqual(ring.popFront(), 1);
        try std.testing.expectEqual(ring.len(), 0);

        try std.testing.expectEqual(ring.popFront(), null);
    }

    {
        var ring = RingBuffer(u32).init(std.testing.allocator);
        defer ring.deinit();

        try ring.pushFront(1);
        try std.testing.expectEqual(ring.len(), 1);
        try ring.pushFront(2);
        try std.testing.expectEqual(ring.len(), 2);
        try std.testing.expectEqual(ring.popFront(), 2);
        try std.testing.expectEqual(ring.len(), 1);

        try std.testing.expectEqual(ring.popFront(), 1);
        try std.testing.expectEqual(ring.len(), 0);

        try ring.pushFront(3);
        try std.testing.expectEqual(ring.len(), 1);
        try std.testing.expectEqual(ring.popFront(), 3);
        try std.testing.expectEqual(ring.len(), 0);

        try ring.pushFront(4);
        try std.testing.expectEqual(ring.len(), 1);
        try std.testing.expectEqual(ring.popFront(), 4);
        try std.testing.expectEqual(ring.len(), 0);

        try std.testing.expectEqual(ring.popFront(), null);
        try std.testing.expectEqual(ring.popFront(), null);
        try std.testing.expectEqual(ring.popFront(), null);
    }
}

test "RingBuffer: append to back and front" {
    {
        var ring = RingBuffer(u32).init(std.testing.allocator);
        defer ring.deinit();

        try ring.pushFront(1);
        try ring.pushBack(2);
        try ring.pushFront(3);
        try ring.pushBack(4);
        try ring.pushFront(5);
        try ring.pushBack(6);
        try ring.pushFront(7);
        try ring.pushBack(8);

        try std.testing.expectEqual(ring.len(), 8);

        try std.testing.expectEqual(ring.popBack(), 8);
        try std.testing.expectEqual(ring.popFront(), 7);
        try std.testing.expectEqual(ring.popBack(), 6);
        try std.testing.expectEqual(ring.popFront(), 5);
        try std.testing.expectEqual(ring.popBack(), 4);
        try std.testing.expectEqual(ring.popFront(), 3);
        try std.testing.expectEqual(ring.popBack(), 2);
        try std.testing.expectEqual(ring.popFront(), 1);
    }
}

test "RingBuffer: realloc with tail before head" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    try ring.pushBack(1);
    try ring.pushBack(2);
    try ring.pushBack(3);
    try ring.pushBack(4);
    try ring.pushBack(5);
    try ring.pushBack(6);
    try ring.pushBack(7);
    try ring.pushBack(8);
    try ring.pushBack(9);

    try std.testing.expectEqual(ring.len(), 9);

    try std.testing.expectEqual(ring.popBack(), 9);
    try std.testing.expectEqual(ring.popBack(), 8);
    try std.testing.expectEqual(ring.popBack(), 7);
    try std.testing.expectEqual(ring.popBack(), 6);
    try std.testing.expectEqual(ring.popBack(), 5);
    try std.testing.expectEqual(ring.popBack(), 4);
    try std.testing.expectEqual(ring.popBack(), 3);
    try std.testing.expectEqual(ring.popBack(), 2);
    try std.testing.expectEqual(ring.popBack(), 1);
    try std.testing.expectEqual(ring.popBack(), null);
}

test "RingBuffer: realloc with tail before head, after wrapping" {
    var ring = try RingBuffer(u32).initCapacity(std.testing.allocator, 8);
    defer ring.deinit();

    // Wrap front around to the last index, push until it is at the first index again
    try ring.pushFront(0);
    try ring.pushFront(1);
    try ring.pushFront(2);
    try ring.pushFront(3);
    try ring.pushFront(4);
    try ring.pushFront(5);
    try ring.pushFront(6);
    try ring.pushFront(7);

    // wrap the head to the last index
    try std.testing.expectEqual(ring.popBack(), 0);

    try std.testing.expectEqual(ring.len(), 7);
    try ring.ensureTotalCapacity(ring.capacity() + 1);
    try std.testing.expectEqual(ring.len(), 7);

    try std.testing.expectEqual(ring.popBack(), 1);
    try std.testing.expectEqual(ring.popBack(), 2);
    try std.testing.expectEqual(ring.popBack(), 3);
    try std.testing.expectEqual(ring.popBack(), 4);
    try std.testing.expectEqual(ring.popBack(), 5);
    try std.testing.expectEqual(ring.popBack(), 6);
    try std.testing.expectEqual(ring.popBack(), 7);
    try std.testing.expectEqual(ring.popBack(), null);
}

test "RingBuffer: realloc with tail after head, shorter head" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    try ring.pushBack(2);
    try ring.pushBack(1);
    try ring.pushFront(3);
    try ring.pushFront(4);
    try ring.pushFront(5);
    try ring.pushFront(6);
    try ring.pushFront(7);
    try ring.pushFront(8);
    try ring.pushFront(9);

    try std.testing.expectEqual(ring.len(), 9);

    try std.testing.expectEqual(ring.popBack(), 1);
    try std.testing.expectEqual(ring.popBack(), 2);
    try std.testing.expectEqual(ring.popBack(), 3);
    try std.testing.expectEqual(ring.popBack(), 4);
    try std.testing.expectEqual(ring.popBack(), 5);
    try std.testing.expectEqual(ring.popBack(), 6);
    try std.testing.expectEqual(ring.popBack(), 7);
    try std.testing.expectEqual(ring.popBack(), 8);
    try std.testing.expectEqual(ring.popBack(), 9);
    try std.testing.expectEqual(ring.popBack(), null);
}

test "RingBuffer: realloc with tail after head, shorter tail" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    try ring.pushFront(2);
    try ring.pushFront(1);
    try ring.pushBack(3);
    try ring.pushBack(4);
    try ring.pushBack(5);
    try ring.pushBack(6);
    try ring.pushBack(7);
    try ring.pushBack(8);
    try ring.pushBack(9);

    try std.testing.expectEqual(ring.len(), 9);

    try std.testing.expectEqual(ring.popBack(), 9);
    try std.testing.expectEqual(ring.popBack(), 8);
    try std.testing.expectEqual(ring.popBack(), 7);
    try std.testing.expectEqual(ring.popBack(), 6);
    try std.testing.expectEqual(ring.popBack(), 5);
    try std.testing.expectEqual(ring.popBack(), 4);
    try std.testing.expectEqual(ring.popBack(), 3);
    try std.testing.expectEqual(ring.popBack(), 2);
    try std.testing.expectEqual(ring.popBack(), 1);
    try std.testing.expectEqual(ring.popBack(), null);
}

test "RingBuffer: get" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    try ring.pushBack(1);
    try ring.pushBack(2);
    try ring.pushBack(3);
    try ring.pushBack(4);
    try ring.pushBack(5);
    try ring.pushBack(6);
    try ring.pushBack(7);
    try ring.pushBack(8);

    try std.testing.expectEqual(ring.len(), 8);

    try std.testing.expectEqual(ring.get(0).?.*, 1);
    try std.testing.expectEqual(ring.get(1).?.*, 2);
    try std.testing.expectEqual(ring.get(2).?.*, 3);
    try std.testing.expectEqual(ring.get(3).?.*, 4);
    try std.testing.expectEqual(ring.get(4).?.*, 5);
    try std.testing.expectEqual(ring.get(5).?.*, 6);
    try std.testing.expectEqual(ring.get(6).?.*, 7);
    try std.testing.expectEqual(ring.get(7).?.*, 8);
    try std.testing.expectEqual(ring.get(8), null);
}

test "RingBuffer: get, wrapping" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    try ring.pushFront(4);
    try ring.pushFront(3);
    try ring.pushFront(2);
    try ring.pushFront(1);
    try ring.pushBack(5);
    try ring.pushBack(6);
    try ring.pushBack(7);
    try ring.pushBack(8);

    try std.testing.expectEqual(ring.len(), 8);

    try std.testing.expectEqual(ring.get(0).?.*, 1);
    try std.testing.expectEqual(ring.get(1).?.*, 2);
    try std.testing.expectEqual(ring.get(2).?.*, 3);
    try std.testing.expectEqual(ring.get(3).?.*, 4);
    try std.testing.expectEqual(ring.get(4).?.*, 5);
    try std.testing.expectEqual(ring.get(5).?.*, 6);
    try std.testing.expectEqual(ring.get(6).?.*, 7);
    try std.testing.expectEqual(ring.get(7).?.*, 8);
    try std.testing.expectEqual(ring.get(8), null);
}

test "RingBuffer: iterators" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    try ring.pushBack(1);
    try ring.pushBack(2);
    try ring.pushBack(3);
    try ring.pushBack(4);
    try ring.pushBack(5);
    try ring.pushBack(6);
    try ring.pushBack(7);
    try ring.pushBack(8);

    var iter = ring.iter();
    var expected: u32 = 1;
    while (iter.next()) |i| {
        try std.testing.expectEqual(i.*, expected);
        expected += 1;
    }

    try std.testing.expectEqual(expected, 9);

    var iter_rev = ring.iterReverse();
    while (iter_rev.next()) |i| {
        expected -= 1;
        try std.testing.expectEqual(i.*, expected);
    }

    try std.testing.expectEqual(expected, 1);
}

test "RingBuffer: popBack while iterating forward" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    try ring.pushBack(1);
    try ring.pushBack(2);
    try ring.pushBack(3);
    try ring.pushBack(4);
    try ring.pushBack(5);

    var iter = ring.iter();
    try std.testing.expectEqual(iter.next().?.*, 1);
    _ = ring.popBack().?;
    try std.testing.expectEqual(iter.next().?.*, 2);
    _ = ring.popBack().?;
    try std.testing.expectEqual(iter.next().?.*, 3);
    _ = ring.popBack().?;
    try std.testing.expectEqual(iter.next(), null);
}

test "RingBuffer: popBack while iterating backwards" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    try ring.pushBack(1);
    try ring.pushBack(2);
    try ring.pushBack(3);
    try ring.pushBack(4);
    try ring.pushBack(5);

    var iter = ring.iterReverse();
    try std.testing.expectEqual(iter.next().?.*, 5);
    _ = ring.popBack().?;
    try std.testing.expectEqual(iter.next().?.*, 3);
    _ = ring.popBack().?;
    try std.testing.expectEqual(iter.next().?.*, 1);
    _ = ring.popBack().?;
    try std.testing.expectEqual(iter.next(), null);
}

test "RingBuffer: popFront while iterating backwards" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    try ring.pushBack(1);
    try ring.pushBack(2);
    try ring.pushBack(3);
    try ring.pushBack(4);
    try ring.pushBack(5);

    var iter = ring.iterReverse();
    try std.testing.expectEqual(iter.next().?.*, 5);
    _ = ring.popFront().?;
    try std.testing.expectEqual(iter.next().?.*, 4);
    _ = ring.popFront().?;
    try std.testing.expectEqual(iter.next().?.*, 3);
    _ = ring.popFront().?;
    try std.testing.expectEqual(iter.next(), null);
}

test "RingBuffer: popFront while iterating forwards" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    try ring.pushBack(1);
    try ring.pushBack(2);
    try ring.pushBack(3);
    try ring.pushBack(4);
    try ring.pushBack(5);

    var iter = ring.iter();
    try std.testing.expectEqual(iter.next().?.*, 1);
    _ = ring.popFront().?;
    try std.testing.expectEqual(iter.next().?.*, 3);
    _ = ring.popFront().?;
    try std.testing.expectEqual(iter.next().?.*, 5);
    _ = ring.popFront().?;
    try std.testing.expectEqual(iter.next(), null);
}

test "RingBuffer: deinit while iterating" {
    var ring = RingBuffer(u32).init(std.testing.allocator);

    try ring.pushBack(1);
    try ring.pushBack(2);
    try ring.pushBack(3);
    try ring.pushBack(4);
    try ring.pushBack(5);

    var iter = ring.iter();
    ring.deinit();
    try std.testing.expectEqual(iter.next(), null);
}

test "RingBuffer: pushBack while iterating forward" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    var iter = ring.iter();
    try ring.pushBack(1);
    try std.testing.expectEqual(iter.next().?.*, 1);
    try ring.pushBack(2);
    try ring.pushBack(3);
    try ring.pushBack(4);
    try std.testing.expectEqual(iter.next().?.*, 2);
    try std.testing.expectEqual(iter.next().?.*, 3);
    try ring.pushBack(5);
    try std.testing.expectEqual(iter.next().?.*, 4);
    try std.testing.expectEqual(iter.next().?.*, 5);
}

test "RingBuffer: pushFront while iterating backwards" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    var iter = ring.iterReverse();
    try ring.pushFront(1);
    try std.testing.expectEqual(iter.next().?.*, 1);
    try ring.pushFront(2);
    try ring.pushFront(3);
    try ring.pushFront(4);
    try std.testing.expectEqual(iter.next().?.*, 2);
    try std.testing.expectEqual(iter.next().?.*, 3);
    try ring.pushFront(5);
    try std.testing.expectEqual(iter.next().?.*, 4);
    try std.testing.expectEqual(iter.next().?.*, 5);
}

test "RingBuffer: pushBack while iterating backwards" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    var iter = ring.iterReverse();
    try ring.pushBack(1);
    try std.testing.expectEqual(iter.next().?.*, 1);
    try ring.pushBack(2);
    try ring.pushBack(3);
    try ring.pushBack(4);
    try std.testing.expectEqual(iter.next().?.*, 3);
    try std.testing.expectEqual(iter.next().?.*, 2);
    try ring.pushBack(5);
    try std.testing.expectEqual(iter.next().?.*, 2);
    try std.testing.expectEqual(iter.next().?.*, 1);
}

test "RingBuffer: pushFront while iterating forwards" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    var iter = ring.iter();
    try ring.pushFront(1);
    try std.testing.expectEqual(iter.next().?.*, 1);
    try ring.pushFront(2);
    try ring.pushFront(3);
    try ring.pushFront(4);
    try std.testing.expectEqual(iter.next().?.*, 3);
    try std.testing.expectEqual(iter.next().?.*, 2);
    try ring.pushFront(5);
    try std.testing.expectEqual(iter.next().?.*, 2);
    try std.testing.expectEqual(iter.next().?.*, 1);
}

test "RingBuffer: stress pushBack" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    var i: u32 = 0;
    while (i < 1024 * 8) : (i += 1) {
        try ring.pushBack(i * 2);
    }
}

test "RingBuffer: stress pushFront" {
    var ring = RingBuffer(u32).init(std.testing.allocator);
    defer ring.deinit();

    var i: u32 = 0;
    while (i < 1024 * 8) : (i += 1) {
        try ring.pushFront(i * 2);
    }
}

test "RingBuffer: stress ensureTotalCapacity" {
    var ring = RingBuffer(u32).init(std.testing.FailingAllocator.init(std.testing.allocator, 1).allocator());
    defer ring.deinit();

    const num_elems = 1024 * 8;
    var i: u32 = 0;

    try ring.ensureTotalCapacity(num_elems);
    while (i < num_elems) : (i += 1) {
        try ring.pushFront(i * 2);
    }
}

test "RingBuffer: initCapacity" {
    var ring = try RingBuffer(u32).initCapacity(std.testing.FailingAllocator.init(std.testing.allocator, 1).allocator(), 5);
    defer ring.deinit();

    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        try ring.pushFront(i * 2);
    }
}
