const std = @import("std");
const stdout = std.io.getStdOut().writer();

const sdl = @import("zsdl2");
const zsdl2_ttf = @import("zsdl2_ttf");
const zopengl = @import("zopengl");
const gl = zopengl.bindings;
const Font = @import("zsdl2_ttf").Font;
const ztracy = @import("ztracy");

//////////////////////////////
///   Globals
//////////////////////////////
var window: *sdl.Window = undefined;
//var renderer: *sdl.Renderer = undefined;

const window_title = "Title";
const screenWidth: f32 = 600.0;
const screenHeight: f32 = 480.0;

const fps: u64 = 60;
var quit: bool = false;
var event: sdl.Event = undefined;

const Red: sdl.Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
//////////////////////////////
///   End of Globals
//////////////////////////////

const triangle_vertices = [_]f32{
    // x.y (NDC space)
    0.0,  0.5,
    -0.5, -0.5,
    0.5,  -0.5,
};

const triangle_colors = [_]f32{
    // r, g, b
    1.0, 0.0, 0.0, // red
    0.0, 1.0, 0.0, // green
    0.0, 0.0, 1.0, // blue
};

const rectangle_vertices = [_]f32{
    // Triangle 1
    0.5,  0.5,
    -0.5, 0.5,
    -0.5, -0.5,
    // Triangle 2
    0.5,  0.5,
    -0.5, -0.5,
    0.5,  -0.5,
};

const rectangle_colors = [_]f32{
    1.0, 0.0, 0.0,
    0.0, 1.0, 0.0,
    0.0, 0.0, 1.0,
    1.0, 0.0, 0.0,
    0.0, 0.0, 1.0,
    1.0, 1.0, 0.0,
};

var vao: u32 = undefined;
var vbo: u32 = undefined;
var colors_vbo: u32 = undefined;
var shader_program: u32 = undefined;
const vertex_shader_source =
    \\#version 430 core
    \\layout (location = 0) in vec2 aPos;
    \\layout (location =1) in vec3 aColor;
    \\out vec3 vertexColor;
    \\
    \\void main(){
    \\gl_Position = vec4(aPos,0.0,1.0);
    \\vertexColor = aColor;
    \\}
;

// Dont delete og
// const fragment_shader_source =
//     \\#version 430 core
//     \\in vec3 vertexColor;
//     \\out vec4 FragColor;
//     \\uniform vec2 u_resolution;
//     \\
//     \\void main() {
//     \\    vec2 uv = gl_FragCoord.xy / u_resolution;
//     \\    vec2 centered = (uv - 0.5) * 2.0;
//     \\    centered.x *= u_resolution.x / u_resolution.y;
//     \\
//     \\    float radius = 0.5;
//     \\    float dist = length(centered);
//     \\
//     \\    // Use smoothstep for soft edge transition
//     \\    float alpha = 1.0 - smoothstep(radius - 0.01, radius, dist);
//     \\
//     \\    // Apply the alpha to create smooth edge
//     \\    FragColor = vec4(vertexColor, alpha);
//     \\}
// ;

const fragment_shader_source =
    \\#version 430 core
    \\in vec3 vertexColor;
    \\out vec4 FragColor;
    \\uniform vec2 u_resolution;
    \\uniform vec2 center;
    \\uniform float radius;
    \\
    \\void main() {
    \\    vec2 uv = gl_FragCoord.xy / u_resolution;
    \\    vec2 norm_center = center / u_resolution;
    \\    vec2 centered = (uv - norm_center) * 2.0;
    \\    centered.x *= u_resolution.x / u_resolution.y;
    \\    float norm_radius = radius / u_resolution.y; 
    \\
    \\    float dist = length(centered);
    \\    float alpha = 1.0 - smoothstep(norm_radius - 0.01, norm_radius, dist);
    \\    FragColor = vec4(vertexColor, alpha);
    \\}
;

const vertex_shader_source_slice: []const u8 = vertex_shader_source[0..];
const fragment_shader_source_slice: []const u8 = fragment_shader_source[0..];
fn createShaderProgram(vertex_shader_slice: []const u8, fragment_shader_slice: []const u8) !u32 {
    const allocator = std.heap.c_allocator;
    const vert_src = try std.mem.concat(allocator, u8, &.{ vertex_shader_slice, "\x00" });
    defer allocator.free(vert_src);
    const vert_ptr: [*c]const u8 = @ptrCast(vert_src.ptr);
    const vert_shader = gl.createShader(gl.VERTEX_SHADER);
    defer gl.deleteShader(vert_shader);
    gl.shaderSource(vert_shader, 1, @ptrCast(&vert_ptr), 0);
    gl.compileShader(vert_shader);

    var success: i32 = 0;
    gl.getShaderiv(vert_shader, gl.COMPILE_STATUS, &success);
    if (success == 0) {
        printShaderLog(vert_shader);
        return error.VertexShaderCompileFailed;
    }

    const frag_shader = gl.createShader(gl.FRAGMENT_SHADER);
    defer gl.deleteShader(frag_shader);
    const frag_src = try std.mem.concat(allocator, u8, &.{ fragment_shader_slice, "\x00" });
    defer allocator.free(frag_src);
    const frag_ptr: [*c]const u8 = @ptrCast(frag_src.ptr);

    gl.shaderSource(frag_shader, 1, @ptrCast(&frag_ptr), 0);
    gl.compileShader(frag_shader);
    gl.getShaderiv(frag_shader, gl.COMPILE_STATUS, &success);
    if (success == 0) {
        printShaderLog(frag_shader);
        return error.FragmentShaderCompileFailed;
    }

    shader_program = gl.createProgram();
    gl.attachShader(shader_program, vert_shader);
    gl.attachShader(shader_program, frag_shader);
    gl.linkProgram(shader_program);
    gl.getProgramiv(shader_program, gl.COMPILE_STATUS, &success);
    if (success == 0) {
        printProgramLog(shader_program);
        return error.ShaderProgramLinkingFailed;
    }
    return shader_program;
}
fn printProgramLog(program: u32) void {
    var max_length: gl.Int = undefined;
    gl.getProgramiv(program, gl.INFO_LOG_LENGTH, &max_length);

    if (max_length > 1) {
        const allocator = std.heap.page_allocator;
        const buffer = allocator.alloc(u8, @intCast(max_length)) catch return;
        defer allocator.free(buffer);

        var actual_length: gl.Int = undefined;
        gl.getProgramInfoLog(program, max_length, &actual_length, buffer.ptr);
        std.debug.print("Program linkage log:\n{s}\n", .{buffer});
    }
}
fn printShaderLog(shader: gl.Uint) void {
    var maxLength: gl.Int = undefined;
    gl.getShaderiv(shader, gl.INFO_LOG_LENGTH, &maxLength);

    if (maxLength > 1) {
        const allocator = std.heap.page_allocator;
        const buffer = allocator.alloc(u8, @intCast(maxLength)) catch return;
        defer allocator.free(buffer);

        var actualLength: gl.Int = undefined;
        gl.getShaderInfoLog(shader, maxLength, &actualLength, buffer.ptr);
        std.debug.print("Shader compile log:\n{s}\n", .{buffer});
    }
}
fn setupObject(comptime object_vertex_len: usize, object_vertices: [object_vertex_len]f32, comptime object_colors_len: usize, object_colors: [object_colors_len]f32) void {
    gl.genVertexArrays(1, &vao);
    gl.genBuffers(1, &vbo);
    gl.genBuffers(1, &colors_vbo);

    gl.bindVertexArray(vao);

    // Positon buffer
    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(object_vertices)), &object_vertices, gl.STATIC_DRAW);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 2 * @sizeOf(f32), null);
    gl.enableVertexAttribArray(0);

    // Color buffer
    gl.bindBuffer(gl.ARRAY_BUFFER, colors_vbo);
    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(object_colors)), &object_colors, gl.STATIC_DRAW);
    gl.vertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 3 * @sizeOf(f32), null);
    gl.enableVertexAttribArray(1);

    gl.bindBuffer(gl.ARRAY_BUFFER, 0);
    gl.bindVertexArray(0);
}
// Initialization Function , should be the first to run
fn init() !void {

    // zig fmt: off
    try sdl.init(.{ 
        .video = true,
        .audio = false,
    });
 
    window = try sdl.createWindow(
        window_title,
        sdl.Window.pos_centered,
        sdl.Window.pos_centered,
        screenWidth,
        screenHeight,
        .{
        .opengl = true,
        },
    );
    // zig fmt: on
    const context: sdl.gl.Context = try sdl.gl.createContext(window);
    try zopengl.loadCoreProfile(sdl.gl.getProcAddress, 4, 3);
    std.debug.print("Created GL context: {*}\n", .{context});
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    shader_program = try createShaderProgram(vertex_shader_source_slice, fragment_shader_source_slice);
    setupObject(rectangle_vertices.len, rectangle_vertices, rectangle_colors.len, rectangle_colors);
    //    renderer = try sdl.createRenderer(window, -1, .{ .accelerated = true });
}

// Deinitialization Funcaiton should be the last to run
fn deinit() void {
    var vbo_buffers = [_]u32{ vbo, colors_vbo };
    gl.deleteBuffers(@as(i32, @intCast(vbo_buffers.len)), &vbo_buffers[0]);
    var vao_buffers = [_]u32{vao};
    gl.deleteVertexArrays(@as(i32, @intCast(vao_buffers.len)), &vao_buffers[0]);
    gl.deleteProgram(shader_program);
    window.destroy();
    //renderer.destroy();
}

// returns wheather to quit or not
fn shouldQuit() bool {
    return quit;
}

// Handles Any user input
fn eventHandler(inputevent: *sdl.Event) !void {
    switch (inputevent.type) {
        .quit => quit = true,
        .keydown => |_| {
            if (inputevent.key.keysym.sym == .escape) quit = true;
        },
        else => {},
    }
}

fn manageTime(last_time: *i128) !void {
    const frame_time_ns: u64 = 1_000_000_000 / fps; // Convert FPS to nanoseconds
    const current_time = std.time.nanoTimestamp();

    const elapsed_time_ns: u64 = @intCast(current_time - last_time.*);
    const elapsed_time_ms = @as(f64, @floatFromInt(elapsed_time_ns)) / 1_000_000.0; // Convert ns to ms
    if (elapsed_time_ns < frame_time_ns) {
        const remaining_time_ns = frame_time_ns - elapsed_time_ns;
        std.time.sleep(remaining_time_ns);

        const actual_fps = 1_000_000_000.0 / @as(f64, @floatFromInt(elapsed_time_ns));
        try stdout.print("Frame Time: {d:.4} ms, FPS: {d:.2}\n", .{ elapsed_time_ms, actual_fps });
    }
    last_time.* = std.time.nanoTimestamp(); // Update last_time Before sleeping

}
// Main event loop
fn eventLoop() !void {
    var last_time: i128 = std.time.nanoTimestamp();

    while (!shouldQuit()) {
        while (sdl.pollEvent(&event)) {
            try eventHandler(&event);
        }

        try updateAndRender();
        try manageTime(&last_time);
    } else {
        deinit();
    }
}
// # 28 28 28
// Updates and clears
var x = screenWidth / 2.0;
var y = screenHeight / 2.0;
fn updateAndRender() !void {
    //try renderer.clear();
    //try renderer.setDrawColor(Red);
    //renderer.present();
    y -= 0.1;
    gl.viewport(0, 0, screenWidth, screenHeight);

    // zig fmt: off
    gl.clearColor(
    0.10980392156862745,
    0.10980392156862745,
    0.10980392156862745,
    1.0
    );
    // zig fmt: on
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(shader_program);
    const resolution_location = gl.getUniformLocation(shader_program, "u_resolution");
    gl.uniform2f(resolution_location, screenWidth, screenHeight);

    const center_location = gl.getUniformLocation(shader_program, "center");
    gl.uniform2f(center_location, x, y);

    const radius_location = gl.getUniformLocation(shader_program, "radius");
    gl.uniform1f(radius_location, 30);

    gl.bindVertexArray(vao);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
    sdl.gl.swapWindow(window);
}
pub fn main() !void {
    const main_loop = ztracy.ZoneNC(@src(), "Main Loop", 0xff_00_ff);
    defer main_loop.End();
    try init();
    try eventLoop();
}
