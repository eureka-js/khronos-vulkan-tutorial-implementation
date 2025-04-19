const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "");
    @cInclude("GLFW/glfw3.h");
});

const std = @import("std");
const builtin = @import("builtin");

const WIDTH: u32 = 800;
const HEIGHT: u32 = 600;

const validationLayers: []const [*c]const u8 = &[_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
const enableValidationLayers = builtin.mode == .Debug;

fn CreateDebugUtilMessengerEXT(
    instance: c.VkInstance,
    pCreateInfo: *c.VkDebugUtilsMessengerCreateInfoEXT,
    pAllocator: ?*const c.VkAllocationCallbacks,
    pDebugMessenger: *c.VkDebugUtilsMessengerEXT,
) c.VkResult {
    const func: c.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
    if (func) |f| {
        return f(instance, pCreateInfo, pAllocator, pDebugMessenger);
    } else {
        return c.VK_ERROR_EXTENSION_NOT_PRESENT;
    }
}

fn DestroyDebugUtilsMessengerEXT(instance: c.VkInstance, debugMessenger: c.VkDebugUtilsMessengerEXT, pAllocator: ?*const c.VkAllocationCallbacks) void {
    const func: c.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
    if (func) |f| {
        f(instance, debugMessenger, pAllocator);
    }
}

const QueueFamilyIndices = struct {
    graphicsFamily: ?u32,

    fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphicsFamily != null;
    }
};

const HelloTriangleApplication = struct {
    window: ?*c.GLFWwindow = undefined,

    instance: c.VkInstance = undefined,
    debugMessenger: c.VkDebugUtilsMessengerEXT = undefined,

    physicalDevice: c.VkPhysicalDevice = @ptrCast(c.VK_NULL_HANDLE),
    device: c.VkDevice = undefined,

    graphicsQueue: c.VkQueue = undefined,

    allocator: *const std.mem.Allocator,

    pub fn run(self: *HelloTriangleApplication) !void {
        try self.initWindow();
        try self.initVulkan();
        try self.mainLoop();
        try self.cleanup();
    }

    fn initWindow(self: *HelloTriangleApplication) !void {
        if (c.glfwInit() == c.GLFW_FALSE) {
            return error.FailedGlfwInitialization;
        }

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

        self.window = c.glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", null, null);
    }

    fn initVulkan(self: *HelloTriangleApplication) !void {
        try self.createInstance();
        try self.setupDebugMessenger();
        try self.pickPhysicalDevice();
        try self.createLogicalDevice();
    }

    fn mainLoop(self: *HelloTriangleApplication) !void {
        while (c.glfwWindowShouldClose(self.window.?) == 0) {
            c.glfwPollEvents();
        }
    }

    fn cleanup(self: *HelloTriangleApplication) !void {
        if (enableValidationLayers) {
            DestroyDebugUtilsMessengerEXT(self.instance, self.debugMessenger, null);
        }

        c.vkDestroyDevice(self.device, null);

        c.vkDestroyInstance(self.instance, null);

        c.glfwDestroyWindow(self.window);

        c.glfwTerminate();
    }

    fn createInstance(self: *HelloTriangleApplication) !void {
        if (enableValidationLayers and !(try checkValidationLayerSupport(self.allocator))) {
            return error.ValidationLayersNotFound;
        }

        const appInfo: c.VkApplicationInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "Hello Triangle",
            .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName = "No Engine",
            .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = c.VK_API_VERSION_1_0,
        };

        const extensions = try getRequiredExtensions(self.allocator);
        defer extensions.deinit();
        var createInfo: c.VkInstanceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &appInfo,
            .enabledExtensionCount = @intCast(extensions.items.len),
            .ppEnabledExtensionNames = extensions.items.ptr,
        };
        var debugCreateInfo: c.VkDebugUtilsMessengerCreateInfoEXT = undefined;
        if (enableValidationLayers) {
            createInfo.enabledLayerCount = validationLayers.len;
            createInfo.ppEnabledLayerNames = validationLayers.ptr;

            populateDebugMessengerCreateInfo(&debugCreateInfo);
            createInfo.pNext = &debugCreateInfo;
        } else {
            createInfo.enabledLayerCount = 0;

            createInfo.pNext = null;
        }

        if (c.vkCreateInstance(&createInfo, null, &self.instance) != c.VK_SUCCESS) {
            return error.FailedToCreateInstance;
        }
    }

    fn populateDebugMessengerCreateInfo(createInfo: *c.VkDebugUtilsMessengerCreateInfoEXT) void {
        createInfo.* = .{
            .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
            .pfnUserCallback = debugCallback,
            .pUserData = null,
        };
    }

    fn setupDebugMessenger(self: *HelloTriangleApplication) !void {
        if (!enableValidationLayers) {
            return;
        }

        var createInfo: c.VkDebugUtilsMessengerCreateInfoEXT = undefined;
        populateDebugMessengerCreateInfo(&createInfo);
        if (CreateDebugUtilMessengerEXT(self.instance, &createInfo, null, &self.debugMessenger) != c.VK_SUCCESS) {
            return error.FailedToSetupDebugMessenger;
        }
    }

    fn pickPhysicalDevice(self: *HelloTriangleApplication) !void {
        var deviceCount: u32 = 0;
        _ = c.vkEnumeratePhysicalDevices(self.instance, &deviceCount, null);
        if (deviceCount == 0) {
            return error.FailedToFindGpuWithVulkanSupport;
        }

        const devices = try self.allocator.alloc(c.VkPhysicalDevice, deviceCount);
        defer self.allocator.free(devices);
        _ = c.vkEnumeratePhysicalDevices(self.instance, &deviceCount, devices.ptr);
        for (devices) |device| {
            if (try isDeviceSuitable(device, self.allocator)) {
                self.physicalDevice = device;
                break;
            }
        }

        const vkNullHandle: c.VkPhysicalDevice = @ptrCast(c.VK_NULL_HANDLE);
        if (self.physicalDevice == vkNullHandle) {
            return error.FailedToFindASuitableGpu;
        }
    }

    fn createLogicalDevice(self: *HelloTriangleApplication) !void {
        const indices: QueueFamilyIndices = try findQueueFamilies(self.physicalDevice, self.allocator);

        var queueCreateInfo: c.VkDeviceQueueCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = indices.graphicsFamily.?,
            .queueCount = 1,
        };
        var queuePriority: f32 = 1.0;
        queueCreateInfo.pQueuePriorities = &queuePriority;

        var deviceFeatures: c.VkPhysicalDeviceFeatures = .{};

        var createInfo: c.VkDeviceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pQueueCreateInfos = &queueCreateInfo,
            .queueCreateInfoCount = 1,
            .pEnabledFeatures = &deviceFeatures,
            .enabledExtensionCount = 0,
        };

        if (c.vkCreateDevice(self.physicalDevice, &createInfo, null, &self.device) != c.VK_SUCCESS) {
            return error.FailedToCreateLogicalDevice;
        }

        c.vkGetDeviceQueue(self.device, indices.graphicsFamily.?, 0, &self.graphicsQueue);
    }

    fn isDeviceSuitable(device: c.VkPhysicalDevice, allocator: *const std.mem.Allocator) !bool {
        const indices: QueueFamilyIndices = try findQueueFamilies(device, allocator);

        return indices.isComplete();
    }

    fn findQueueFamilies(device: c.VkPhysicalDevice, allocator: *const std.mem.Allocator) !QueueFamilyIndices {
        var indices: QueueFamilyIndices = .{ .graphicsFamily = null };

        var queueFamilyCount: u32 = 0;
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
        const queueFamilies = try allocator.alloc(c.VkQueueFamilyProperties, queueFamilyCount);
        defer allocator.free(queueFamilies);
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);
        for (queueFamilies, 0..) |queueFamily, i| {
            if ((queueFamily.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) != 0) {
                indices.graphicsFamily = @intCast(i);
            }

            if (indices.isComplete()) {
                break;
            }
        }

        return indices;
    }

    fn getRequiredExtensions(allocator: *const std.mem.Allocator) !std.ArrayList([*c]const u8) {
        var glfwExtensionCount: u32 = 0;
        const glfwExtensions: [*c][*c]const u8 = c.glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

        var extensions = std.ArrayList(@TypeOf(glfwExtensions.*)).init(allocator.*);
        if (enableValidationLayers) {
            try extensions.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        }

        return extensions;
    }

    fn checkValidationLayerSupport(allocator: *const std.mem.Allocator) !bool {
        var layerCount: u32 = 0;
        _ = c.vkEnumerateInstanceLayerProperties(&layerCount, null);

        const availableLayers = try allocator.alloc(c.VkLayerProperties, layerCount);
        defer allocator.free(availableLayers);
        _ = c.vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.ptr);

        outer: for (validationLayers) |layerName| {
            const name = std.mem.sliceTo(layerName, 0);
            for (availableLayers) |property| {
                const property_name = std.mem.sliceTo(&property.layerName, 0);
                if (std.mem.eql(u8, name, property_name)) {
                    continue :outer;
                }
            }

            return false;
        }
        return true;
    }

    fn debugCallback(
        messageSeverity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
        messageType: c.VkDebugUtilsMessageTypeFlagsEXT,
        pCallbackData: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
        pUserData: ?*anyopaque,
    ) callconv(.C) c.VkBool32 {
        _ = &messageSeverity;
        _ = &messageType;
        _ = &pUserData;
        std.debug.print("validation layer: {s}\n", .{pCallbackData.*.pMessage});

        return c.VK_FALSE;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app: HelloTriangleApplication = .{ .allocator = &allocator };

    try app.run();
}
