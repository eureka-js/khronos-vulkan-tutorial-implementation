pub const glfw =  @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "");
    @cInclude("GLFW/glfw3.h");
});
const vk = @import("vulkan.zig").vk;

pub extern fn glfwCreateWindowSurface(
    instance:  vk.VkInstance,
    handle:    ?*anyopaque,
    allocator: ?*const vk.VkAllocationCallbacks,
    surface:   *vk.VkSurfaceKHR,
) vk.VkResult;
