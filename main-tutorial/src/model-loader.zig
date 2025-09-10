const c = @cImport({
    @cInclude("tiny_obj_loader_c.h");
});

const std    = @import("std");
const Vertex = @import("vertex.zig").Vertex;

const MODEL_PATH = "models/viking_room.obj";

fn fileReader(
    ctx:          ?*anyopaque,
    filename:     [*c]const u8,
    _:            c_int,
    _:            [*c]const u8,
    buff:         [*c][*c]u8,
    len:          [*c]usize,
) callconv(.c) void {
    if (ctx == null) return;

    const allocator: *std.mem.Allocator = @alignCast(@ptrCast(ctx.?));

    const fname = std.mem.span(filename);
    const file = std.fs.cwd().openFile(fname, .{}) catch return;
    defer file.close();

    const data = file.readToEndAlloc(allocator.*, std.math.maxInt(usize)) catch return;

    buff.* = data.ptr;
    len.* = data.len;
}

pub fn loadModel(
    vertices:  *std.ArrayList(Vertex),
    indices:   *std.ArrayList(u32),
    allocator: *const std.mem.Allocator,
) !void {
    var attrib:       c.tinyobj_attrib_t      = undefined;
    var shapes:       [*]c.tinyobj_shape_t    = undefined;
    var numShapes:    usize                   = undefined;
    var materials:    [*]c.tinyobj_material_t = undefined;
    var numMaterials: usize                   = undefined;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arenaAllocator = arena.allocator();

    const retCode = c.tinyobj_parse_obj(
        &attrib,
        @ptrCast(&shapes), &numShapes,
        @ptrCast(&materials), &numMaterials,
        MODEL_PATH,
        fileReader, @constCast(@ptrCast(&arenaAllocator)),
        c.TINYOBJ_FLAG_TRIANGULATE
    );
    if      (retCode == c.TINYOBJ_ERROR_EMPTY)             {return error.TinyobjErrorEmpty;}
    else if (retCode == c.TINYOBJ_ERROR_INVALID_PARAMETER) {return error.TinyobjErrorInvalidParameter;}
    else if (retCode == c.TINYOBJ_ERROR_FILE_OPERATION)    {return error.TinyobjErrorFileOperation;}

    vertices.* = std.ArrayList(Vertex).init(allocator.*);
    indices.*  = std.ArrayList(u32).init(allocator.*);

    var uniqueVertices = std.HashMap(Vertex, u32, Vertex.KeyContext, std.hash_map.default_max_load_percentage).init(allocator.*);
    defer uniqueVertices.deinit();

    for (0..numShapes) |i| {
        const shape = shapes[i];

        var currOffset: usize = shape.face_offset;
        for (0..shape.length) |_| {
            // NOTE: The assumption is that the flag TINYOBJ_FLAG_TRIANGULATE splits all polygons into triangles
            // so there is no need to depend on the field attrib.face_num_verts. (2025-08-27)
            //const vertCount: usize = @intCast(attrib.face_num_verts[i]);
            const vertCount = 3;

            // NOTE: The assumption is that attrib.faces is an array of vertices and not faces. (2025-08-27)
            for (attrib.faces[currOffset..currOffset + vertCount]) |index| {
                const v_idx:  usize  = @intCast(index.v_idx);
                const vt_idx: usize  = @intCast(index.vt_idx);
                const vertex: Vertex = .{
                    .pos      = .{
                        attrib.vertices[3 * v_idx + 0],
                        attrib.vertices[3 * v_idx + 1],
                        attrib.vertices[3 * v_idx + 2],
                    },
                    .texCoord = .{
                        attrib.texcoords[2 * vt_idx + 0],
                        1.0 - attrib.texcoords[2 * vt_idx + 1],
                    },
                    .color    = .{1.0, 1.0, 1.0},
                };

                if (!uniqueVertices.contains(vertex)) {
                    try uniqueVertices.put(vertex, @intCast(vertices.*.items.len));
                    try vertices.*.append(vertex);
                }

                try indices.*.append(uniqueVertices.get(vertex).?);
            }

            currOffset += vertCount;
        }
    }
}

