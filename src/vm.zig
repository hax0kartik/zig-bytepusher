const std = @import("std");
const c = @cImport({
    @cInclude("SDL.h");
});

const vm = @This();

ram: []u8 = undefined,
colormap: [256]u32 = undefined,
pixels: []u32 = undefined,

width: u32 = undefined,
height: u32 = undefined,
scale: u8 = undefined,

window: *c.SDL_Window = undefined,
renderer: *c.SDL_Renderer = undefined,
texture: *c.SDL_Texture = undefined,

audio: c.SDL_AudioDeviceID = undefined,

pub fn init(self: *vm, allocator: *const std.mem.Allocator, filename: []const u8) !void {
    self.* = .{};
    self.ram = try allocator.alloc(u8, 16 * 1024 * 1024);
    for (self.ram) |*v| v.* = 0;
    _ = try std.fs.cwd().readFile(filename, self.ram);

    self.colormap = comptime blk: {
        var colormap: [256]u32 = undefined;
        for (0..6) |r| {
            for (0..6) |g| {
                for (0..6) |b| {
                    colormap[(r * 36) + (g * 6) + b] = (r * 0x33) << 16 | (g * 0x33) << 8 | (b * 0x33);
                }
            }
        }

        break :blk colormap;
    };

    self.width = 256;
    self.height = 256;
    self.scale = 3;

    const size: u32 = self.width * self.height;
    self.pixels = try allocator.alloc(u32, size);

    const res = c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO);
    std.debug.print("SDL_Init : {}\n", .{res});

    self.window = c.SDL_CreateWindow(
        "zig-bytepusher",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        @intCast(self.width * self.scale),
        @intCast(self.height * self.scale),
        c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE,
    ) orelse @panic("Could not create windows");

    self.renderer = c.SDL_CreateRenderer(
        self.window,
        0,
        c.SDL_RENDERER_PRESENTVSYNC,
    ) orelse @panic("Could not create renderer");

    self.texture = c.SDL_CreateTexture(
        self.renderer,
        c.SDL_PIXELFORMAT_BGRA32,
        c.SDL_TEXTUREACCESS_STATIC,
        @intCast(self.width),
        @intCast(self.height),
    ) orelse @panic("Could not create texture");

    const audioSpec = c.SDL_AudioSpec{
        .freq = 15360,
        .format = c.AUDIO_S8,
        .channels = 1,
        .samples = 256,
    };

    self.audio = c.SDL_OpenAudioDevice(0, 0, &audioSpec, 0, 0);
    c.SDL_PauseAudioDevice(self.audio, 0);
}

pub fn deinit(self: *vm, allocator: *const std.mem.Allocator) void {
    c.SDL_DestroyRenderer(self.renderer);
    c.SDL_DestroyWindow(self.window);
    c.SDL_Quit();

    allocator.free(self.pixels);
    allocator.free(self.ram);
}

pub fn run(self: *vm) bool {
    var sdlevent: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&sdlevent) != 0) {
        switch (sdlevent.type) {
            c.SDL_QUIT => return false,
            else => break,
        }
    }

    var pc = readval(self, 2);
    // There is only one type of instruction.
    // This instruction copies 1 byte from a memory location to another, and then performs an unconditional jump.
    for (0..65536) |_| {
        const A = readval(self, pc);
        const B = readval(self, pc + 3);
        self.ram[B] = self.ram[A];

        const C = readval(self, pc + 6);
        pc = C;
    }

    const in_addr: u32 = @as(u32, self.ram[5]) << 16;
    for (0..self.pixels.len) |pixel_idx| {
        const in: u32 = self.ram[pixel_idx + in_addr];
        const converted: u32 = self.colormap[in];
        self.pixels[pixel_idx] = converted;
    }

    _ = c.SDL_UpdateTexture(
        self.texture,
        0,
        &self.pixels[0],
        @intCast(self.width * c.SDL_BYTESPERPIXEL(c.SDL_PIXELFORMAT_BGRA32)),
    );

    const aud_addr: u32 = @as(u32, self.ram[6]) << 16 | @as(u32, self.ram[7]) << 8;
    _ = c.SDL_QueueAudio(self.audio, &self.ram[aud_addr], 256);

    _ = c.SDL_RenderClear(self.renderer);
    _ = c.SDL_RenderCopy(self.renderer, self.texture, 0, 0);
    c.SDL_RenderPresent(self.renderer);

    return true;
}

pub fn readval(self: *vm, idx: u32) u32 {
    return @as(u32, self.ram[idx]) << 16 | @as(u32, self.ram[idx + 1]) << 8 | @as(u32, self.ram[idx + 2]) << 0;
}
