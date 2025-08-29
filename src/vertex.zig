const vk   = @import("bindings/vulkan.zig").vk;
const cglm = @import("bindings/cglm.zig").cglm;

const std = @import("std");

pub const Vertex = struct {
    pub const KeyContext = struct {
        pub fn hash(_: KeyContext, a: Vertex) u64 {
            var h = std.hash.Wyhash.init(0);
            h.update(std.mem.asBytes(&a.pos));
            h.update(std.mem.asBytes(&a.color));
            h.update(std.mem.asBytes(&a.texCoord));
            return h.final();
        }

        pub fn eql(_: KeyContext, a: Vertex, b: Vertex) bool {
            return std.mem.eql(f32, &a.pos, &b.pos) and std.mem.eql(f32, &a.color, &b.color) and std.mem.eql(f32, &a.texCoord, &b.texCoord);
        }
    };

    pos:      cglm.vec3,
    color:    cglm.vec3,
    texCoord: cglm.vec2,

    pub fn getBindingDescription() vk.VkVertexInputBindingDescription {
        const bindingDescription: vk.VkVertexInputBindingDescription = .{
            .binding   = 0,
            .stride    = @sizeOf(@This()),
            .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        return bindingDescription;
    }

    pub fn getAttributeDescriptions() []const vk.VkVertexInputAttributeDescription {
        const attributeDescriptions = &[_]vk.VkVertexInputAttributeDescription{
            .{
                .binding  = 0,
                .location = 0,
                .format   = vk.VK_FORMAT_R32G32B32_SFLOAT,
                .offset   = @offsetOf(@This(), "pos"),
            },
            .{
                .binding  = 0,
                .location = 1,
                .format   = vk.VK_FORMAT_R32G32B32_SFLOAT,
                .offset   = @offsetOf(@This(), "color"),
            },
            .{
                .binding  = 0,
                .location = 2,
                .format   = vk.VK_FORMAT_R32G32_SFLOAT,
                .offset   = @offsetOf(@This(), "texCoord"),
            },
        };

        return attributeDescriptions;
    }
};
