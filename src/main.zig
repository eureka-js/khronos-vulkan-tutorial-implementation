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

const deviceExtensions: []const [*c]const u8 = &[_][*c]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

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
    presentFamily: ?u32,

    fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphicsFamily != null and self.presentFamily != null;
    }
};

const SwapChainSupportDetails = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: std.ArrayList(c.VkSurfaceFormatKHR),
    presentModes: std.ArrayList(c.VkPresentModeKHR),

    fn init(allocator: *const std.mem.Allocator) !*SwapChainSupportDetails {
        const details = try allocator.create(SwapChainSupportDetails);
        details.capabilities = undefined;
        details.formats = std.ArrayList(c.VkSurfaceFormatKHR).init(allocator.*);
        details.presentModes = std.ArrayList(c.VkPresentModeKHR).init(allocator.*);

        return details;
    }

    fn deinit(self: *SwapChainSupportDetails, allocator: *const std.mem.Allocator) void {
        self.formats.deinit();
        self.formats = undefined;
        self.presentModes.deinit();
        self.presentModes = undefined;

        allocator.destroy(self);
    }
};

const HelloTriangleApplication = struct {
    window: ?*c.GLFWwindow = undefined,
    surface: c.VkSurfaceKHR = undefined,

    swapChain: c.VkSwapchainKHR = undefined,
    swapChainImages: []c.VkImage = undefined,
    swapChainImageFormat: c.VkFormat = undefined,
    swapChainExtent: c.VkExtent2D = undefined,
    swapChainImageViews: []c.VkImageView = undefined,

    instance: c.VkInstance = undefined,
    debugMessenger: c.VkDebugUtilsMessengerEXT = undefined,

    physicalDevice: c.VkPhysicalDevice = @ptrCast(c.VK_NULL_HANDLE),
    device: c.VkDevice = undefined,

    graphicsQueue: c.VkQueue = undefined,
    presentQueue: c.VkQueue = undefined,

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
        try self.createSurface();
        try self.pickPhysicalDevice();
        try self.createLogicalDevice();
        try self.createSwapChain();
        try self.createImageViews();
    }

    fn mainLoop(self: *HelloTriangleApplication) !void {
        while (c.glfwWindowShouldClose(self.window.?) == 0) {
            c.glfwPollEvents();
        }
    }

    fn cleanup(self: *HelloTriangleApplication) !void {
        for (self.swapChainImageViews) |imageView| {
            c.vkDestroyImageView(self.device, imageView, null);
        }
        self.allocator.free(self.swapChainImageViews);

        c.vkDestroySwapchainKHR(self.device, self.swapChain, null);
        self.allocator.free(self.swapChainImages);
        c.vkDestroyDevice(self.device, null);

        if (enableValidationLayers) {
            DestroyDebugUtilsMessengerEXT(self.instance, self.debugMessenger, null);
        }

        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
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
        var createInfo: c.VkInstanceCreateInfo = .{};
        createInfo.sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        createInfo.pApplicationInfo = &appInfo;
        createInfo.enabledExtensionCount = @intCast(extensions.items.len);
        createInfo.ppEnabledExtensionNames = extensions.items.ptr;
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

    fn createSurface(self: *HelloTriangleApplication) !void {
        if (c.glfwCreateWindowSurface(self.instance, self.window, null, &self.surface) != c.VK_SUCCESS) {
            return error.FailedToCreateAWindowSurface;
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
            if (try isDeviceSuitable(device, self.surface, self.allocator)) {
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
        const indices: QueueFamilyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);

        var queueCreateInfos = std.ArrayList(c.VkDeviceQueueCreateInfo).init(self.allocator.*);
        defer queueCreateInfos.deinit();
        var uniqueQueueFamilies = std.AutoHashMap(u32, void).init(self.allocator.*);
        defer uniqueQueueFamilies.deinit();
        try uniqueQueueFamilies.put(indices.graphicsFamily.?, {});
        try uniqueQueueFamilies.put(indices.presentFamily.?, {});

        const queuePriority: f32 = 1.0;
        var it = uniqueQueueFamilies.iterator();
        while (it.next()) |entry| {
            const queueCreateInfo: c.VkDeviceQueueCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = entry.key_ptr.*,
                .queueCount = 1,
                .pQueuePriorities = &queuePriority,
            };
            try queueCreateInfos.append(queueCreateInfo);
        }

        var deviceFeatures: c.VkPhysicalDeviceFeatures = .{};

        const createInfo: c.VkDeviceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount = @intCast(queueCreateInfos.items.len),
            .pQueueCreateInfos = queueCreateInfos.items.ptr,
            .pEnabledFeatures = &deviceFeatures,
            .enabledExtensionCount = @intCast(deviceExtensions.len),
            .ppEnabledExtensionNames = deviceExtensions.ptr,
        };

        if (c.vkCreateDevice(self.physicalDevice, &createInfo, null, &self.device) != c.VK_SUCCESS) {
            return error.FailedToCreateLogicalDevice;
        }

        c.vkGetDeviceQueue(self.device, indices.graphicsFamily.?, 0, &self.graphicsQueue);
        c.vkGetDeviceQueue(self.device, indices.presentFamily.?, 0, &self.presentQueue);
    }

    fn createSwapChain(self: *HelloTriangleApplication) !void {
        const swapChainSupport = try querySwapChainSupport(self.physicalDevice, self.surface, self.allocator);
        defer swapChainSupport.deinit(self.allocator);

        const surfaceFormat = chooseSwapSurfaceFormat(&swapChainSupport.formats);
        self.swapChainImageFormat = surfaceFormat.format;

        const presentMode = chooseSwapPresentMode(&swapChainSupport.presentModes);

        const extent = chooseSwapExtent(self, &swapChainSupport.capabilities);
        self.swapChainExtent = extent;

        var imageCount: u32 = swapChainSupport.capabilities.minImageCount + 1;
        if (swapChainSupport.capabilities.maxImageCount > 0 and imageCount > swapChainSupport.capabilities.maxImageCount) {
            imageCount = swapChainSupport.capabilities.maxImageCount;
        }

        var createInfo: c.VkSwapchainCreateInfoKHR = .{};
        createInfo.sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
        createInfo.surface = self.surface;
        createInfo.minImageCount = imageCount;
        createInfo.imageFormat = surfaceFormat.format;
        createInfo.imageExtent = extent;
        createInfo.imageArrayLayers = 1;
        createInfo.imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

        const indices: QueueFamilyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);
        const queueFamilyIndices = [_]u32{ indices.graphicsFamily.?, indices.presentFamily.? };
        if (indices.graphicsFamily != indices.presentFamily) {
            createInfo.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
            createInfo.queueFamilyIndexCount = 2;
            createInfo.pQueueFamilyIndices = &queueFamilyIndices;
        } else {
            createInfo.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        }

        createInfo.preTransform = swapChainSupport.capabilities.currentTransform;
        createInfo.compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
        createInfo.presentMode = presentMode;
        createInfo.clipped = c.VK_TRUE;
        createInfo.oldSwapchain = @ptrCast(c.VK_NULL_HANDLE);

        if (c.vkCreateSwapchainKHR(self.device, &createInfo, null, &self.swapChain) != c.VK_SUCCESS) {
            return error.FailedToCreateSwapChain;
        }

        _ = c.vkGetSwapchainImagesKHR(self.device, self.swapChain, &imageCount, null);
        self.swapChainImages = try self.allocator.alloc(c.VkImage, imageCount);
        _ = c.vkGetSwapchainImagesKHR(self.device, self.swapChain, &imageCount, self.swapChainImages.ptr);
    }

    fn createImageViews(self: *HelloTriangleApplication) !void {
        self.swapChainImageViews = try self.allocator.alloc(c.VkImageView, self.swapChainImages.len);
        for (0..self.swapChainImages.len) |i| {
            const createInfo: c.VkImageViewCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = self.swapChainImages[i],
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = self.swapChainImageFormat,
                .components = .{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            if (c.vkCreateImageView(self.device, &createInfo, null, &self.swapChainImageViews[i]) != c.VK_SUCCESS) {
                return error.FailedToCreateImageViews;
            }
        }
    }

    fn chooseSwapSurfaceFormat(availableFormats: *const std.ArrayList(c.VkSurfaceFormatKHR)) c.VkSurfaceFormatKHR {
        for (availableFormats.items) |availableFormat| {
            if (availableFormat.format == c.VK_FORMAT_B8G8R8A8_SRGB and availableFormat.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                return availableFormat;
            }
        }
        return availableFormats.items[0];
    }

    fn chooseSwapPresentMode(availablePresentModes: *const std.ArrayList(c.VkPresentModeKHR)) c.VkPresentModeKHR {
        for (availablePresentModes.items) |availablePresentMode| {
            if (availablePresentMode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
                return availablePresentMode;
            }
        }
        return c.VK_PRESENT_MODE_FIFO_KHR;
    }

    fn chooseSwapExtent(self: *HelloTriangleApplication, capabilities: *const c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
        if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
            return capabilities.currentExtent;
        }

        var width: u32 = undefined;
        var height: u32 = undefined;
        c.glfwGetFramebufferSize(self.window, @ptrCast(&width), @ptrCast(&height));

        const actualExtent: c.VkExtent2D = .{
            .width = std.math.clamp(
                width,
                capabilities.minImageExtent.width,
                capabilities.maxImageExtent.width,
            ),
            .height = std.math.clamp(
                height,
                capabilities.minImageExtent.height,
                capabilities.maxImageExtent.height,
            ),
        };

        return actualExtent;
    }

    fn querySwapChainSupport(device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, allocator: *const std.mem.Allocator) !*SwapChainSupportDetails {
        var details: *SwapChainSupportDetails = try SwapChainSupportDetails.init(allocator);

        _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities);

        var formatCount: u32 = 0;
        _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, null);
        if (formatCount != 0) {
            try details.formats.ensureTotalCapacity(formatCount);
            try details.formats.resize(formatCount);
            _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, details.formats.items.ptr);
        }

        var presentModeCount: u32 = 0;
        _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, null);
        if (presentModeCount != 0) {
            try details.presentModes.ensureTotalCapacity(presentModeCount);
            try details.presentModes.resize(presentModeCount);
            _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, details.presentModes.items.ptr);
        }

        return details;
    }

    fn isDeviceSuitable(device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, allocator: *const std.mem.Allocator) !bool {
        const indices: QueueFamilyIndices = try findQueueFamilies(device, surface, allocator);

        const extensionsSupported: bool = try checkDeviceExtensionSupport(device, allocator);

        if (!extensionsSupported) {
            return false;
        }

        var swapChainSupport: *SwapChainSupportDetails = try querySwapChainSupport(device, surface, allocator);
        defer swapChainSupport.deinit(allocator);
        const swapChainAdequate: bool = swapChainSupport.formats.items.len > 0 and swapChainSupport.presentModes.items.len > 0;

        return indices.isComplete() and swapChainAdequate;
    }

    fn checkDeviceExtensionSupport(device: c.VkPhysicalDevice, allocator: *const std.mem.Allocator) !bool {
        var extensionCount: u32 = 0;
        _ = c.vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, null);

        const availableExtensions = try allocator.alloc(c.VkExtensionProperties, extensionCount);
        defer allocator.free(availableExtensions);
        _ = c.vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, availableExtensions.ptr);

        var requiredExtensions = std.StringHashMap(void).init(allocator.*);
        defer requiredExtensions.deinit();
        for (deviceExtensions) |extensionName| {
            const name = std.mem.span(extensionName);
            try requiredExtensions.put(name, {});
        }
        for (availableExtensions) |extension| {
            const name = std.mem.sliceTo(&extension.extensionName, 0);
            _ = requiredExtensions.remove(name);
        }

        return requiredExtensions.count() == 0;
    }

    fn findQueueFamilies(device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, allocator: *const std.mem.Allocator) !QueueFamilyIndices {
        var indices: QueueFamilyIndices = .{ .graphicsFamily = null, .presentFamily = null };

        var queueFamilyCount: u32 = 0;
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
        const queueFamilies = try allocator.alloc(c.VkQueueFamilyProperties, queueFamilyCount);
        defer allocator.free(queueFamilies);
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);
        for (queueFamilies, 0..) |queueFamily, i| {
            // NOTE: The same queue family used for both drawing and presentation
            // would yield improved performance compared to this loop implementation
            // (even though it can happen in this implementation that the same queue family
            // gets selected for both). (2025-04-19)

            if ((queueFamily.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) != 0) {
                indices.graphicsFamily = @intCast(i);
            }

            var doesSupportPresent: c.VkBool32 = 0;
            _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface, &doesSupportPresent);
            if (doesSupportPresent != 0) {
                indices.presentFamily = @intCast(i);
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

        var extensions = std.ArrayList([*c]const u8).init(allocator.*);
        for (0..glfwExtensionCount) |i| {
            try extensions.append(glfwExtensions[i]);
        }
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
            const name = std.mem.span(layerName);
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
