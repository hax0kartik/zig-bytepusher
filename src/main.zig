const std = @import("std");
const vm = @import("vm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var argIter = try std.process.ArgIterator.initWithAllocator(allocator.*);
    defer argIter.deinit();

    _ = argIter.next().?; //binary Name
    const romFile = argIter.next() orelse @panic("ROM File not provided");
    std.debug.print("ROM File: {s}\n", .{romFile});

    var v: vm = .{};

    try v.init(allocator, romFile);
    defer v.deinit(allocator);
    while (v.run()) {}
}
