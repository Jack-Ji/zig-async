
// channel example
//  producer - worker - consumer model via channels

const std = @import("std");
const print = std.debug.print;

//const Future = @import("zig_async_jack_ji/task.zig").Future;
const Task = @import("zig_async_jack_ji/task.zig").Task;
const Channel = @import("zig_async_jack_ji/channel.zig").Channel;


//fn randomInteger(rand: *const std.Random, min: u32, max: u32) u32{
//  return rand.intRangeLessThan(u32, min, max + 1);
//}


fn worker(input_ch: *Channel(u32), output_ch: *Channel(u32)) void{
  while(true){
    const maybe_num = input_ch.pop();
    if(maybe_num) |num|{
      if(num == 0){ break; } // sentinel to stop
      const cube = num * num * num;
      output_ch.push(cube) catch unreachable;
    }else{
      std.time.sleep(std.time.ns_per_ms * 10); // avoid busy wait
    }
    
    //var seed: u64 = undefined;
    //std.crypto.random.bytes(std.mem.asBytes(&seed));
    //var prng = std.Random.DefaultPrng.init(seed);
    //const rand = prng.random();
    //const rand_delay = randomInteger(&rand, 1, 5);
    //std.time.sleep(rand_delay * std.time.ns_per_s);
    
  }
}


pub fn main() !void{
  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
  defer _ = gpa.deinit();
  const allocator = gpa.allocator();
  
  var input_ch = try Channel(u32).init(allocator);
  defer input_ch.deinit();
  
  var output_ch = try Channel(u32).init(allocator);
  defer output_ch.deinit();
  
  // launch worker thread
  const WorkerTask = Task(worker);
  var worker_future = try WorkerTask.launch(allocator, .{ input_ch, output_ch });
  defer worker_future.deinit();
  
  const inputs = [_]u32{ 2, 3, 4, 5, 6 };
  
  // send data to worker
  for(inputs) |num|{
    input_ch.push(num) catch unreachable;
  }
  
  // send sentinel to stop worker
  input_ch.push(0) catch unreachable;
  
  // collect results
  var received: usize = 0;
  while(received < inputs.len) : (received += 1){
    while(true){
      if(output_ch.pop()) |result|{
        std.debug.print("Receive {d}\n", .{result});
        break;
      }
      std.time.sleep(std.time.ns_per_ms * 5);
    }
  }
  
  worker_future.wait();
  std.debug.print("All done.\n", .{});
}


// zig build-exe ./src/test2.zig -O ReleaseFast -femit-bin=test2
// ./test2
//Receive 8
//Receive 27
//Receive 64
//Receive 125
//Receive 216
//All done.

