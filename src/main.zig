const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "");
    @cInclude("GLFW/glfw3.h");
});

const std = @import("std");

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

const HelloTriangleApplication = struct {
    window: ?*c.GLFWwindow,
    instance: c.VkInstance,
    allocator: std.mem.Allocator,

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

    fn initVulkan(self: *HelloTriangleApplication) !void {
        try self.createInstance();
    }

    fn mainLoop(self: *HelloTriangleApplication) !void {
        while (c.glfwWindowShouldClose(self.window.?) == 0) {
            c.glfwPollEvents();
        }
    }

    fn cleanup(self: *HelloTriangleApplication) !void {
        c.vkDestroyInstance(self.instance, null);

        c.glfwDestroyWindow(self.window);

        c.glfwTerminate();
    }

    fn createInstance(self: *HelloTriangleApplication) !void {
        const appInfo: c.VkApplicationInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "Hello Triangle",
            .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName = "No Engine",
            .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = c.VK_API_VERSION_1_0,
        };

        var glfwExtensionCount: u32 = 0;
        const glfwExtensions: [*c][*c]const u8 = c.glfwGetRequiredInstanceExtensions(&glfwExtensionCount);
        var createInfo: c.VkInstanceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &appInfo,
            .enabledExtensionCount = glfwExtensionCount,
            .ppEnabledExtensionNames = glfwExtensions,
            .enabledLayerCount = 0,
        };

        if (c.vkCreateInstance(&createInfo, null, &self.instance) != c.VK_SUCCESS) {
            return error.FailedToCreateInstance;
        }

        var extensionCount: u32 = 0;
        _ = c.vkEnumerateInstanceExtensionProperties(null, &extensionCount, null);
        const extensions = try self.allocator.alloc(c.VkExtensionProperties, extensionCount);
        defer self.allocator.free(extensions);
        _ = c.vkEnumerateInstanceExtensionProperties(
            null,
            &extensionCount,
            @ptrCast(extensions.ptr),
        );

        try self.areExtensionsSupported(glfwExtensions, glfwExtensionCount, extensions);
    }

    fn areExtensionsSupported(
        _: *HelloTriangleApplication,
        glfwExt: [*c][*c]const u8,
        glfwExtCount: u32,
        ext: []c.VkExtensionProperties,
    ) !void {
        outer: for (glfwExt[0..glfwExtCount]) |name_ptr| {
            const name = std.mem.span(name_ptr);
            for (ext) |item| {
                const ext_name = std.mem.sliceTo(&item.extensionName, 0);
                if (std.mem.eql(u8, name, ext_name)) {
                    continue :outer;
                }
            }

            return error.ExtensionNotSupported;
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app: HelloTriangleApplication = .{
        .window = undefined,
        .instance = undefined,
        .allocator = allocator,
    };

    try app.run();
}
