pub const Future = @import("task.zig").Future;
pub const Task = @import("task.zig").Task;
pub const Channel = @import("channel.zig").Channel;

test "main test" {
    _ = @import("task.zig");
    _ = @import("channel.zig");
}
