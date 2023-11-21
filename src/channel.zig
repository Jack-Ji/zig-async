const std = @import("std");
const testing = std.testing;
const trait = std.meta.trait;

/// Communication channel between threads
pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();
        const Deque = std.fifo.LinearFifo(T, .Dynamic);

        allocator: std.mem.Allocator,
        mutex: std.Thread.Mutex,
        fifo: Deque,

        pub fn init(allocator: std.mem.Allocator) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .allocator = allocator,
                .mutex = std.Thread.Mutex{},
                .fifo = Deque.init(allocator),
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            while (self.fifo.readItem()) |elem| {
                if (comptime trait.hasFn("deinit")(T)) {
                    elem.deinit(); // Destroy data when possible
                }
            }
            self.fifo.deinit();
            self.allocator.destroy(self);
        }

        /// Push data to channel
        pub fn push(self: *Self, data: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.fifo.writeItem(data);
        }

        /// Popped data from channel
        pub const PopResult = struct {
            allocator: std.mem.Allocator,
            elements: std.ArrayList(T),

            pub fn deinit(self: PopResult) void {
                for (self.elements.items) |*data| {
                    if (comptime trait.hasFn("deinit")(T)) {
                        data.deinit(); // Destroy data when possible
                    }
                }
                self.elements.deinit();
            }
        };

        /// Get data from channel, data will be destroyed together with PopResult
        pub fn popn(self: *Self, max_pop: usize) ?PopResult {
            self.mutex.lock();
            defer self.mutex.unlock();
            var result = PopResult{
                .allocator = self.allocator,
                .elements = std.ArrayList(T).init(self.allocator),
            };
            var count = max_pop;
            while (count > 0) : (count -= 1) {
                if (self.fifo.readItem()) |data| {
                    result.elements.append(data) catch unreachable;
                } else {
                    break;
                }
            }
            return if (count == max_pop) null else result;
        }

        /// Get data from channel, user take ownership
        pub fn pop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.fifo.readItem();
        }
    };
}

test "Channel - smoke testing" {
    const MyData = struct {
        d: i32,

        pub fn deinit(self: @This()) void {
            std.debug.print("\ndeinit mydata, d is {d} ", .{self.d});
        }
    };

    const MyChannel = Channel(MyData);
    var channel = try MyChannel.init(std.testing.allocator);
    defer channel.deinit();

    try channel.push(.{ .d = 1 });
    try channel.push(.{ .d = 2 });
    try channel.push(.{ .d = 3 });
    try channel.push(.{ .d = 4 });
    try channel.push(.{ .d = 5 });

    try testing.expect(channel.pop().?.d == 1);
    var result = channel.popn(3).?;
    defer result.deinit();
    try testing.expect(result.elements.items[0].d == 2);
    try testing.expect(result.elements.items[1].d == 3);
    try testing.expect(result.elements.items[2].d == 4);
}
