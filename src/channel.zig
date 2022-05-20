const std = @import("std");
const testing = std.testing;
const trait = std.meta.trait;

/// Communication channel between threads
pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();
        const List = std.TailQueue(T);

        allocator: std.mem.Allocator,
        mutex: std.Thread.Mutex,
        fifo: List,

        pub fn init(allocator: std.mem.Allocator) !*Self {
            var self = try allocator.create(Self);
            self.* = .{
                .allocator = allocator,
                .mutex = std.Thread.Mutex{},
                .fifo = List{},
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            while (self.fifo.popFirst()) |node| {
                if (comptime trait.hasFn("deinit")(T)) {
                    node.data.deinit(); // Destroy data when possible
                }
                self.allocator.destroy(node);
            }
            self.allocator.destroy(self);
        }

        /// Push data to channel
        pub fn push(self: *Self, data: T) !void {
            var node = try self.allocator.create(List.Node);
            node.data = data;
            self.mutex.lock();
            defer self.mutex.unlock();
            self.fifo.prepend(node);
        }

        /// Popped data from channel
        pub const PopResult = struct {
            allocator: std.mem.Allocator,
            nodes: std.ArrayList(*List.Node),

            pub fn deinit(self: PopResult) void {
                for (self.nodes.items) |node| {
                    if (comptime trait.hasFn("deinit")(T)) {
                        node.data.deinit(); // Destroy data when possible
                    }
                    self.allocator.destroy(node);
                }
                self.nodes.deinit();
            }
        };

        /// Get data from channel
        pub fn pop(self: *Self, max_pop: usize) ?PopResult {
            self.mutex.lock();
            defer self.mutex.unlock();
            var result = PopResult{
                .allocator = self.allocator,
                .nodes = std.ArrayList(*List.Node).init(self.allocator),
            };
            var count = max_pop;
            while (count > 0) : (count -= 1) {
                if (self.fifo.pop()) |node| {
                    result.nodes.append(node) catch unreachable;
                } else {
                    break;
                }
            }
            return if (count == max_pop) null else result;
        }
    };
}

test "Channel - smoke testing" {
    const MyData = struct {
        d: i32,

        pub fn deinit(self: *@This()) void {
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

    var result = channel.pop(3).?;
    defer result.deinit();
    try testing.expect(result.nodes.items[0].data.d == 1);
    try testing.expect(result.nodes.items[1].data.d == 2);
    try testing.expect(result.nodes.items[2].data.d == 3);
}
