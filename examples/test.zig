
// task example

const std = @import("std");
const print = std.debug.print;

//const Future = @import("zig_async_jack_ji/task.zig").Future;
const Task = @import("zig_async_jack_ji/task.zig").Task;
//const Channel = @import("zig_async_jack_ji/channel.zig").Channel;


fn randomInteger(rand: *const std.Random, min: u32, max: u32) u32{
  return rand.intRangeLessThan(u32, min, max + 1);
}

fn make_square(number: u32) void{
  var seed: u64 = undefined;
  std.crypto.random.bytes(std.mem.asBytes(&seed));
  var prng = std.Random.DefaultPrng.init(seed);
  const rand = prng.random();
  const rand_delay = randomInteger(&rand, 1, 5);
  std.time.sleep(rand_delay * std.time.ns_per_s);
  
  const result = number * number;
  std.debug.print("{d} -> {d}\n", .{ number, result });
}


pub fn main() !void{
  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
  defer _ = gpa.deinit();
  const allocator = gpa.allocator();
  
  const numbers = [_]u32{ 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 };
  
  var futures: [numbers.len]*Task(make_square).FutureType = undefined;
  
  // launch all tasks
  for(numbers, 0..) |num, i|{
    futures[i] = try Task(make_square).launch(allocator, .{num});
  }

  // wait for all to complete
  for(futures) |future|{
    future.wait();
    future.deinit();
  }
  
  std.debug.print("All tasks completed.\n", .{});
}


// zig build-exe ./src/test.zig -O ReleaseFast -femit-bin=test
// ./test
//10 -> 100
//50 -> 2500
//20 -> 400
//80 -> 6400
//30 -> 900
//70 -> 4900
//60 -> 3600
//100 -> 10000
//40 -> 1600
//90 -> 8100
//All tasks completed.

