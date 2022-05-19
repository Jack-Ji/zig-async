const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const channel = @import("channel.zig");
const hasDeinitFn = std.meta.trait.hasFn("deinit");

/// Represent a value returned by async task in the future.
pub fn Future(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        done: std.Thread.ResetEvent,
        data: ?T,

        pub fn init(allocator: std.mem.Allocator) !*Self {
            var self = try allocator.create(Self);
            self.* = .{
                .allocator = allocator,
                .done = .{},
                .data = null,
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            if (!self.done.isSet()) {
                @panic("future isn't done yet!");
            }
            if (self.data) |data| {
                // Destroy data when possible
                // Only detect one layer of optional/error-union
                switch (@typeInfo(T)) {
                    .Optional => |info| {
                        if (std.meta.trait.isSingleItemPtr(info.child) and
                            hasDeinitFn(@typeInfo(info.child).Pointer.child))
                        {
                            if (data) |d| d.deinit();
                        } else if (hasDeinitFn(info.child)) {
                            if (data) |d| d.deinit();
                        }
                    },
                    .ErrorUnion => |info| {
                        if (std.meta.trait.isSingleItemPtr(info.payload) and
                            hasDeinitFn(@typeInfo(info.payload).Pointer.child))
                        {
                            if (data) |d| d.deinit() else |_| {}
                        } else if (hasDeinitFn(info.payload)) {
                            if (data) |d| d.deinit() else |_| {}
                        }
                    },
                    .Struct => if (hasDeinitFn(T)) data.deinit(),
                    else => {},
                }
            }
            self.allocator.destroy(self);
        }

        /// Wait until data is granted
        /// WARNING: data must be granted after this call, or the function won't return forever
        pub fn wait(self: *Self) T {
            self.done.wait();
            std.debug.assert(self.data != null);
            return self.data.?;
        }

        /// Wait until data is granted or timeout happens
        pub fn timedWait(self: *Self, time_ns: u64) ?T {
            self.done.timedWait(time_ns) catch {};
            return self.data;
        }

        /// Grant data and send signal to waiting threads
        pub fn grant(self: *Self, data: T) void {
            self.data = data;
            self.done.set();
        }
    };
}

/// Arguments to task
pub fn TaskArgs(T1: type, T2: type, T3: type, T4: type, T5: type, T6: type) type {
    return struct {
        args1: T1,
        args2: T2,
        args3: T3,
        args4: T4,
        args5: T5,
        args6: T6,
    };
}

/// Async task runs in another thread
pub fn Task(comptime fun: anytype) type {
    return struct {
        pub const FunType = @TypeOf(fun);
        pub const ArgsType = std.meta.ArgsTuple(FunType);
        pub const ReturnType = @typeInfo(FunType).Fn.return_type.?;
        pub const FutureType = Future(ReturnType);

        /// Internal thread function, run user's function and
        /// grant result to future.
        fn task(future: *FutureType, args: ArgsType) void {
            const ret = @call(.{}, fun, args);
            future.grant(ret);
        }

        /// Create task thread and detach from it
        pub fn launch(allocator: std.mem.Allocator, args: ArgsType) !*FutureType {
            var future = try FutureType.init(allocator);
            errdefer future.deinit();
            var thread = try std.Thread.spawn(.{}, task, .{ future, args });
            thread.detach();
            return future;
        }
    };
}

test "Async Task" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const S = struct {
        const R = struct {
            allocator: std.mem.Allocator,
            v: u32,

            pub fn deinit(self: *@This()) void {
                std.debug.print("\ndeinit R, v is {d}", .{self.v});
                self.allocator.destroy(self);
            }
        };

        fn div(allocator: std.mem.Allocator, a: u32, b: u32) !*R {
            if (b == 0) return error.DivisionByZero;
            var r = try allocator.create(R);
            r.* = .{
                .allocator = allocator,
                .v = @divTrunc(a, b),
            };
            return r;
        }

        fn return_nothing() void {}

        fn long_work(ch: *channel.Channel(u32), a: u32, b: u32) u32 {
            std.time.sleep(std.time.ns_per_s);
            ch.push(std.math.pow(u32, a, 1)) catch unreachable;
            std.time.sleep(std.time.ns_per_ms * 10);
            ch.push(std.math.pow(u32, a, 2)) catch unreachable;
            std.time.sleep(std.time.ns_per_ms * 10);
            ch.push(std.math.pow(u32, a, 3)) catch unreachable;
            return a + b;
        }

        fn add(f1: *Future(u128), f2: *Future(u128)) u128 {
            const a = f1.wait();
            const b = f2.wait();
            return a + b;
        }
    };

    {
        const TestTask = Task(S.div);
        var future = TestTask.launch(std.testing.allocator, .{ std.testing.allocator, 1, 0 }) catch unreachable;
        defer future.deinit();
        try testing.expectError(error.DivisionByZero, future.wait());
        try testing.expectError(error.DivisionByZero, future.timedWait(10).?);
    }

    {
        const TestTask = Task(S.div);
        var future = TestTask.launch(std.testing.allocator, .{ std.testing.allocator, 1, 1 }) catch unreachable;
        defer future.deinit();
        const ret = future.wait();
        try testing.expectEqual(@as(u32, 1), if (ret) |r| r.v else |_| unreachable);
    }

    {
        const TestTask = Task(S.return_nothing);
        var future = TestTask.launch(std.testing.allocator, .{}) catch unreachable;
        future.wait();
        defer future.deinit();
    }

    {
        var ch = try channel.Channel(u32).init(std.testing.allocator);
        defer ch.deinit();

        const TestTask = Task(S.long_work);
        var future = TestTask.launch(std.testing.allocator, .{ ch, 2, 1 }) catch unreachable;
        defer future.deinit();

        try testing.expectEqual(@as(?u32, null), future.timedWait(1));
        try testing.expectEqual(@as(?u32, null), future.timedWait(1));
        try testing.expectEqual(@as(?u32, null), future.timedWait(1));
        try testing.expectEqual(@as(?u32, null), future.timedWait(1));
        try testing.expectEqual(@as(?u32, null), future.timedWait(1));
        try testing.expectEqual(@as(?u32, null), future.timedWait(1));
        try testing.expectEqual(@as(?u32, null), future.timedWait(1));
        try testing.expectEqual(@as(?u32, null), future.timedWait(1));
        try testing.expectEqual(@as(?channel.Channel(u32).PopResult, null), ch.pop(1));
        try testing.expectEqual(@as(u32, 3), future.wait());

        var result = ch.pop(3).?;
        try testing.expectEqual(result.nodes.items.len, 3);
        try testing.expectEqual(@as(u32, 2), result.nodes.items[0].data);
        try testing.expectEqual(@as(u32, 4), result.nodes.items[1].data);
        try testing.expectEqual(@as(u32, 8), result.nodes.items[2].data);
        result.deinit();
    }

    {
        const TestTask = Task(S.add);
        var fs: [100]*TestTask.FutureType = undefined;
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        fs[0] = try TestTask.FutureType.init(arena.allocator());
        fs[1] = try TestTask.FutureType.init(arena.allocator());
        fs[0].grant(0);
        fs[1].grant(1);

        // compute 100th fibonacci number
        var i: u32 = 2;
        while (i < 100) : (i += 1) {
            fs[i] = try TestTask.launch(arena.allocator(), .{ fs[i - 2], fs[i - 1] });
        }
        try testing.expectEqual(@as(u128, 218922995834555169026), fs[99].wait());
    }
}
