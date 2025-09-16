const std = @import("std");

const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_ttf/SDL_ttf.h");
    @cInclude("SDL3_image/SDL_image.h");
});

const cwd = std.fs.cwd;

const Vec2 = struct {
    x: f32,
    y: f32,
};

const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const PROG_NAME = "pres";
const W = 1200;
const H = 800;

const BG: Color = .{
    .r = 0,
    .g = 0,
    .b = 0,
    .a = 0,
};

const FG: Color = .{
    .r = 1.0,
    .g = 1.0,
    .b = 1.0,
    .a = 1.0,
};

const DEFAULT_BODY_SIZE = 20.0;

var window: ?*c.SDL_Window = undefined;
pub var renderer: ?*c.SDL_Renderer = undefined;
var refresh_rate_ns: u64 = undefined;
var font_bytes: []const u8 = "";
var font_bold_italic_bytes: []const u8 = "";
var arena_impl: std.heap.ArenaAllocator = undefined;
var regular_font: *c.TTF_Font = undefined;

fn setRefreshRate(display_fps: f32) void {
    refresh_rate_ns = @intFromFloat(1_000_000 / display_fps);
}

fn sleepNextFrame() void {
    std.Thread.sleep(refresh_rate_ns);
}

pub fn main() !void {
    //Initialize SDL
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        c.SDL_Log("SDL could not initialize! SDL error: %s\n", c.SDL_GetError());
        return;
    }
    defer c.SDL_Quit();

    if (!c.TTF_Init()) {
        std.debug.print("TTF failed init\n", .{});
        return;
    }
    defer c.TTF_Quit();

    arena_impl = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    font_bold_italic_bytes = cwd().readFileAlloc(arena, "/usr/share/fonts/TTF/TinosNerdFont-BoldItalic.ttf", 10_000_000) catch |e| {
        std.debug.print("Couldn't open font: {any}\n", .{e});
        return;
    };
    font_bytes = cwd().readFileAlloc(arena, "/usr/share/fonts/TTF/TinosNerdFont-Regular.ttf", 10_000_000) catch |e| {
        std.debug.print("Couldn't open font: {any}\n", .{e});
        return;
    };

    regular_font = c.TTF_OpenFontIO(c.SDL_IOFromConstMem(font_bold_italic_bytes.ptr, font_bold_italic_bytes.len), false, 62.0) orelse {
        std.debug.print("Couldn't open font: {s}\n", .{c.SDL_GetError()});
        return;
    };
    defer c.TTF_CloseFont(regular_font);

    const args = try std.process.argsAlloc(arena);
    if (args.len > 1) {
        //editor.window.openFile(args[1]);
    }

    const display_mode = c.SDL_GetCurrentDisplayMode(c.SDL_GetPrimaryDisplay()) orelse {
        c.SDL_Log("Could not get display mode! SDL error: %s\n", c.SDL_GetError());
        return;
    };
    setRefreshRate(display_mode.*.refresh_rate);

    //const win_flags = c.SDL_WINDOW_INPUT_FOCUS | c.SDL_WINDOW_HIGH_PIXEL_DENSITY | c.SDL_WINDOW_MAXIMIZED | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_BORDERLESS;
    const win_flags = c.SDL_WINDOW_INPUT_FOCUS | c.SDL_WINDOW_HIGH_PIXEL_DENSITY | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_BORDERLESS;

    if (!c.SDL_CreateWindowAndRenderer(PROG_NAME, W, H, win_flags, &window, &renderer)) {
        std.debug.print("Couldn't create window/renderer:", .{});
        return;
    }

    _ = c.SDL_StartTextInput(window);

    loop();
}

var animating = false;
var last_tick: i64 = 0;
var was_pos = Vec2{
    .x = -1.0,
    .y = -1.0,
};
var zoom_scalar: f32 = 1.0;
var ctrl_down = false;
var viewport = Vec2{};

fn loop() void {
    var running = true;
    var event: c.SDL_Event = undefined;
    while (running) {
        const current_tick = std.time.microTimestamp();
        defer last_tick = current_tick;
        const dt = @as(f32, @floatFromInt(current_tick - last_tick)) / std.time.us_per_s;
        var did_input = false;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    running = false;
                },
                c.SDL_EVENT_KEY_DOWN => {
                    did_input = true;
                    ctrl_down = event.key.mod & c.SDL_KMOD_CTRL != 0;
                    switch (event.key.key) {
                        c.SDLK_ESCAPE => {
                            running = false;
                        },
                        else => {},
                    }
                },
                c.SDL_EVENT_KEY_UP => {
                    ctrl_down = event.key.mod & c.SDL_KMOD_CTRL != 0;
                },
                c.SDL_EVENT_TEXT_INPUT => {
                    if (ctrl_down) {
                        continue;
                    }
                    did_input = true;
                },
                else => {},
            }
        }
        if (!running) {
            break;
        }

        defer sleepNextFrame();

        if (!animating and !did_input and last_tick > 0) {
            continue;
        }

        draw(dt);
    }
}

fn draw(_: f32) void {
    _ = c.SDL_SetRenderDrawColorFloat(renderer, BG.r, BG.g, BG.b, BG.a);
    _ = c.SDL_RenderClear(renderer);
    _ = c.SDL_SetRenderDrawColorFloat(renderer, FG.r, FG.g, FG.b, FG.a);
    drawText(regular_font, "hi", FG, 100.0, 100.0);
    _ = c.SDL_RenderPresent(renderer);
}

pub fn drawText(font: ?*c.TTF_Font, text: []const u8, color: Color, x: f32, y: f32) void {
    if (text.len == 0) {
        return;
    }
    const surface = c.TTF_RenderText_Blended(font, text.ptr, text.len, asColor(color)) orelse return;
    defer c.SDL_DestroySurface(surface);
    const texture = c.SDL_CreateTextureFromSurface(renderer, surface) orelse return;
    defer c.SDL_DestroyTexture(texture);

    const dst = c.SDL_FRect{
        .x = x,
        .y = y,
        .h = @floatFromInt(texture.*.h),
        .w = @floatFromInt(texture.*.w),
    };

    _ = c.SDL_RenderTexture(renderer, texture, null, &dst);
}

pub fn str(s: []const u8) [:0]const u8 {
    const static = struct {
        var buffer: [2048]u8 = undefined;
    };
    return std.fmt.bufPrintZ(&static.buffer, "{s}", .{s}) catch {
        static.buffer[0] = 0;
        return static.buffer[0..1 :0];
    };
}

pub fn strdim(font: ?*c.TTF_Font, s: []const u8) struct { w: f32, h: f32 } {
    if (s.len == 0) {
        return .{
            .w = 0,
            .h = 0,
        };
    }
    var w: c_int = 0;
    var h: c_int = 0;
    _ = c.TTF_GetStringSize(font, s.ptr, s.len, &w, &h);
    return .{
        .w = @floatFromInt(w),
        .h = @floatFromInt(h),
    };
}

fn asColor(v: Color) c.SDL_Color {
    return c.SDL_Color{
        .r = @intFromFloat(v.r * 255),
        .g = @intFromFloat(v.g * 255),
        .b = @intFromFloat(v.b * 255),
        .a = @intFromFloat(v.a * 255),
    };
}
