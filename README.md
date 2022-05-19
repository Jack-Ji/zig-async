# zig-async
An simple and easy to use async task library for zig.

## Async Task
Task running in separate thread, returns `Future` after launched.
`Future` represents task's return value in the future, which can be queried by using its waiting methods.
The wrapped data within `Future` will be automatically destroyed if supported by struct (has `deinit` method);

```zig
const Result = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    c: u32,

    /// Will be called automatically when destorying future
    pub fn init(allocator: std.mem.Allocator, _c: u32) !*Self {
        var self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .c = _c,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }
};

fn add(a: u32, b: u32) !*Result {
    return try Result.init(std.testing.allocator, a + b);
}

const MyTask = Task(add);
var future = try MyTask.launch(std.testing.allocator, .{ 2, 1 });
defer future.deinit();
const ret = future.wait();
try testing.expectEqual(@as(u32, 3), if (ret) |d| d.c else |_| unreachable);
```

## Channel
Generic message queue used for communicating between threads.
Capable of free memory automatically if supported by embedded struct (has `deinit` method).

```zig
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
```
