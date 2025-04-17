const c = @cImport({
    @cDefine("GLFW_INLCUDE_VULKAN", "");
    @cInclude("GLFW/glfw3.h");
});

const std = @import("std");

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

const HelloTriangleApplication = struct {
    window: ?*c.GLFWwindow,

    pub fn run(self: *HelloTriangleApplication) !void {
        try self.initWindow();
        try self.initVulkan();
        try self.mainLoop();
        try self.cleanup();
    }

    fn initWindow(self: *HelloTriangleApplication) !void {
        _ = c.glfwInit();

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

        self.window = c.glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", null, null);
    }

    fn initVulkan(_: *HelloTriangleApplication) !void {}

    fn mainLoop(self: *HelloTriangleApplication) !void {
        while (c.glfwWindowShouldClose(self.window.?) == 0) {
            c.glfwPollEvents();
        }
    }

    fn cleanup(self: *HelloTriangleApplication) !void {
        c.glfwDestroyWindow(self.window);

        c.glfwTerminate();
    }
};

pub fn main() !void {
    var app: HelloTriangleApplication = .{ .window = undefined };

    try app.run();
}
