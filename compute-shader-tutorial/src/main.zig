const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "");
    @cInclude("GLFW/glfw3.h");

    @cInclude("cglm/cglm.h");
});

const std     = @import("std");
const builtin = @import("builtin");

const WIDTH:  u32 = 800;
const HEIGHT: u32 = 600;

const PARTICLE_COUNT: u32 = 8192;

const MAX_FRAMES_IN_FLIGHT: u32 = 2;

const validationLayers       = &[_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
const enableValidationLayers = builtin.mode == .Debug;

const deviceExtensions       = &[_][*c]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

fn createDebugUtilMessengerEXT(
    instance:        c.VkInstance,
    pCrateInfo:      *c.VkDebugUtilsMessengerCreateInfoEXT,
    pAllocator:      ?*const c.VkAllocationCallbacks,
    pDebugMessenger: *c.VkDebugUtilsMessengerEXT,
) c.VkResult {
    const func: c.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
    if (func) |f| {
        return f(instance, pCrateInfo, pAllocator, pDebugMessenger);
    } else {
        return c.VK_ERROR_EXTENSION_NOT_PRESENT;
    }
}

fn DestroyDebugUtilsMessengerEXT(
    instance:       c.VkInstance,
    debugMessenger: c.VkDebugUtilsMessengerEXT,
    pAllocator:     ?*const c.VkAllocationCallbacks,
) void {
    const func: c.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
    if (func) |f| {
        f(instance, debugMessenger, pAllocator);
    }
}

const UniformBufferObject = struct {
    deltaTime: f32 = 1.0,
};

const Particle = struct {
    position: c.vec2,
    velocity: c.vec2,
    color:    c.vec4,

    pub fn getBindingDescription() c.VkVertexInputBindingDescription {
        return .{
            .binding   = 0,
            .stride    = @sizeOf(@This()),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        };
    }

    pub fn getAttributeDescriptions() []const c.VkVertexInputAttributeDescription {
        return &.{
            .{
                .binding  = 0,
                .location = 0,
                .format   = c.VK_FORMAT_R32G32_SFLOAT,
                .offset   = @offsetOf(@This(), "position"),
            },
            .{
                .binding  = 0,
                .location = 1,
                .format   = c.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset   = @offsetOf(@This(), "color"),
            },
        };
    }
};

const QueueFamilyIndices = struct {
    graphicsAndCompute: ?u32 = null,
    present:            ?u32 = null,
    transfer:           ?u32 = null,

    fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphicsAndCompute != null and self.present != null and self.transfer != null;
    }
};

const SwapChainSupportDetails = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats:      std.ArrayList(c.VkSurfaceFormatKHR),
    presentModes: std.ArrayList(c.VkPresentModeKHR),
    allocator:    *const std.mem.Allocator,

    fn init(allocator: *const std.mem.Allocator) !*SwapChainSupportDetails {
        const details = try allocator.create(SwapChainSupportDetails);
        details.capabilities = undefined;
        details.formats      = std.ArrayList(c.VkSurfaceFormatKHR).init(allocator.*);
        details.presentModes = std.ArrayList(c.VkPresentModeKHR).init(allocator.*);
        details.allocator    = allocator;

        return details;
    }

    fn deinit(self: *SwapChainSupportDetails) void {
        self.formats.deinit();
        self.presentModes.deinit();
        self.formats      = undefined;
        self.presentModes = undefined;

        self.allocator.destroy(self);
    }
};

const ComputeShaderApplication = struct {
    window:  ?*c.GLFWwindow = undefined,
    surface: c.VkSurfaceKHR = undefined,

    physicalDevice: c.VkPhysicalDevice = @ptrCast(c.VK_NULL_HANDLE),
    device:         c.VkDevice         = undefined,

    graphicsQueue: c.VkQueue = undefined,
    computeQueue:  c.VkQueue = undefined,
    transferQueue: c.VkQueue = undefined,
    presentQueue:  c.VkQueue = undefined,

    swapChain:             c.VkSwapchainKHR   = undefined,
    swapChainImages:       []c.VkImage        = undefined,
    swapChainImageFormat:  c.VkFormat         = undefined,
    swapChainExtent:       c.VkExtent2D       = undefined,
    swapChainImageViews:   []c.VkImageView    = undefined,
    swapChainFramebuffers: []c.VkFramebuffer  = undefined,

    renderPass:       c.VkRenderPass     = undefined,
    pipelineLayout:   c.VkPipelineLayout = undefined,
    graphicsPipeline: c.VkPipeline       = undefined,

    computeDescriptorSetLayout: c.VkDescriptorSetLayout = undefined,
    computePipelineLayout:      c.VkPipelineLayout      = undefined,
    computePipeline:            c.VkPipeline            = undefined,

    graphicsAndComputeCommandPool:  c.VkCommandPool = undefined,
    transferCommandPool:            c.VkCommandPool = undefined,

    descriptorPool:        c.VkDescriptorPool                      = undefined,
    computeDescriptorSets: [MAX_FRAMES_IN_FLIGHT]c.VkDescriptorSet = undefined,

    commandBuffers:        [MAX_FRAMES_IN_FLIGHT]c.VkCommandBuffer = undefined,
    computeCommandBuffers: [MAX_FRAMES_IN_FLIGHT]c.VkCommandBuffer = undefined,

    imageAvailableSemaphores:  [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = undefined,
    renderFinishedSemaphores:  [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = undefined,
    computeFinishedSemaphores: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = undefined,
    inFlightFences:            [MAX_FRAMES_IN_FLIGHT]c.VkFence     = undefined,
    computeInFlightFences:     [MAX_FRAMES_IN_FLIGHT]c.VkFence     = undefined,
    currentFrame: u32 = 0,

    shaderStorageBuffers:       [MAX_FRAMES_IN_FLIGHT]c.VkBuffer       = undefined,
    shaderStorageBuffersMemory: [MAX_FRAMES_IN_FLIGHT]c.VkDeviceMemory = undefined,

    uniformBuffers:       [MAX_FRAMES_IN_FLIGHT]c.VkBuffer           = undefined,
    uniformBuffersMemory: [MAX_FRAMES_IN_FLIGHT]c.VkDeviceMemory     = undefined,
    uniformBuffersMapped: [MAX_FRAMES_IN_FLIGHT]*UniformBufferObject = undefined,

    graphicsAndComputeQueueIndex: u32 = undefined,
    presentQueueIndex:            u32 = undefined,

    instance:       c.VkInstance               = undefined,
    debugMessenger: c.VkDebugUtilsMessengerEXT = undefined,

    lastFrameTime: f32 = 0.0,

    framebufferResized: bool = false,

    lastTime: f64 = 0.0,

    allocator: *const std.mem.Allocator,


    fn run(self: *ComputeShaderApplication) !void {
        try self.initWindow();
        try self.initVulkan();
        try self.mainLoop();
        try self.cleanup();
    }

    fn initWindow(self: *ComputeShaderApplication) !void {
        if (c.glfwInit() == c.GLFW_FALSE) {
            return error.FailedGLFWInitialization;
        }

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

        self.window = c.glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", null, null);
        c.glfwSetWindowUserPointer(self.window, self);
        _ = c.glfwSetFramebufferSizeCallback(self.window, framebufferResizeCallback);

        self.lastTime = c.glfwGetTime();
    }

    fn framebufferResizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
        _, _ = .{width, height};
        const app: *ComputeShaderApplication = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)));
        app.framebufferResized = true;
    }

    fn initVulkan(self: *ComputeShaderApplication) !void {
        try self.createInstance();
        try self.setupDebugMessenger();
        try self.createSurface();
        try self.pickPhysicalDevice();
        try self.createLogicalDevice();
        try self.createSwapChain();
        try self.createImageViews();
        try self.createRenderPass();
        try self.createComputeDescriptorSetLayout();
        try self.createGraphicsPipeline();
        try self.createComputePipeline();
        try self.createFramebuffers();
        try self.createCommandPool();
        try self.createShaderStorageBuffers();
        try self.createUniformBuffers();
        try self.createDescriptorPool();
        try self.createComputeDescriptorSets();
        try self.createCommandBuffers();
        try self.createComputeCommandBuffers();
        try self.createSyncObjects();
    }

    fn mainLoop(self: *ComputeShaderApplication) !void {
        while (c.glfwWindowShouldClose(self.window.?) == 0) {
            c.glfwPollEvents();
            try self.drawFrame();
            // We want to animate the particle system using the last frames time to get smooth, frame-rate independent animation
            const currentTime: f64 = c.glfwGetTime();
            self.lastFrameTime = @floatCast((currentTime - self.lastTime) * 1000.0);
            self.lastTime = currentTime;
        }

        _ = c.vkDeviceWaitIdle(self.device);
    }

    fn cleanup(self: *ComputeShaderApplication) !void {
        self.cleanupSwapChain();

        c.vkDestroyPipeline(self.device, self.computePipeline, null);
        c.vkDestroyPipelineLayout(self.device, self.computePipelineLayout, null);

        c.vkDestroyPipeline(self.device, self.graphicsPipeline, null);
        c.vkDestroyPipelineLayout(self.device, self.pipelineLayout, null);

        c.vkDestroyRenderPass(self.device, self.renderPass, null);

        for (0..self.uniformBuffers.len) |i| {
            c.vkDestroyBuffer(self.device, self.uniformBuffers[i], null);
            c.vkFreeMemory(self.device, self.uniformBuffersMemory[i], null);
        }

        c.vkDestroyDescriptorPool(self.device, self.descriptorPool, null);

        c.vkDestroyDescriptorSetLayout(self.device, self.computeDescriptorSetLayout, null);

        for (0..self.shaderStorageBuffers.len) |i| {
            c.vkDestroyBuffer(self.device, self.shaderStorageBuffers[i], null);
            c.vkFreeMemory(self.device, self.shaderStorageBuffersMemory[i], null);
        }

        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            c.vkDestroySemaphore(self.device, self.renderFinishedSemaphores[i], null);
            c.vkDestroySemaphore(self.device, self.imageAvailableSemaphores[i], null);
            c.vkDestroySemaphore(self.device, self.computeFinishedSemaphores[i], null);
            c.vkDestroyFence(self.device, self.inFlightFences[i], null);
            c.vkDestroyFence(self.device, self.computeInFlightFences[i], null);
        }

        c.vkDestroyCommandPool(self.device, self.graphicsAndComputeCommandPool, null);
        c.vkDestroyCommandPool(self.device, self.transferCommandPool, null);

        c.vkDestroyDevice(self.device, null);

        if (enableValidationLayers) {
            DestroyDebugUtilsMessengerEXT(self.instance, self.debugMessenger, null);
        }

        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);

        c.glfwDestroyWindow(self.window);

        c.glfwTerminate();
    }

    fn cleanupSwapChain(self: *ComputeShaderApplication) void {
        for (self.swapChainFramebuffers) |framebuffer| {
            c.vkDestroyFramebuffer(self.device, framebuffer, null);
        }
        self.allocator.free(self.swapChainFramebuffers);

        for (self.swapChainImageViews) |imageView| {
            c.vkDestroyImageView(self.device, imageView, null);
        }
        self.allocator.free(self.swapChainImageViews);

        c.vkDestroySwapchainKHR(self.device, self.swapChain, null);
        self.allocator.free(self.swapChainImages);
    }

    fn createInstance(self: *ComputeShaderApplication) !void {
        if (enableValidationLayers and !(try checkValidationLayerSupport(self.allocator))) {
            return error.ValidationLayersRequestedButNotAvailable;
        }

        const appInfo: c.VkApplicationInfo = .{
            .sType              = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName   = "Hello Triangle",
            .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName        = "No Engine",
            .engineVersion      = c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion         = c.VK_API_VERSION_1_0,
        };

        const extensions = try getRequiredExtensions(self.allocator);
        defer extensions.deinit();
        var createInfo: c.VkInstanceCreateInfo = .{
            .sType                   = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo        = &appInfo,
            .enabledExtensionCount   = @intCast(extensions.items.len),
            .ppEnabledExtensionNames = extensions.items.ptr,
        };
        if (enableValidationLayers) {
            createInfo.enabledLayerCount   = validationLayers.len;
            createInfo.ppEnabledLayerNames = validationLayers.ptr;
        }

        if (c.vkCreateInstance(&createInfo, null, &self.instance) != c.VK_SUCCESS) {
            return error.FailedToCreateInstance;
        }
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

    fn getRequiredExtensions(allocator: *const std.mem.Allocator) !std.ArrayList([*c]const u8) {
        var glfwExtensionCount: u32 = 0;
        const glfwExtensions = c.glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

        var extensions = std.ArrayList([*c]const u8).init(allocator.*);
        for (0..glfwExtensionCount) |i| {
            try extensions.append(glfwExtensions[i]);
        }
        if (enableValidationLayers) {
            try extensions.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        }

        return extensions;
    }

    fn setupDebugMessenger(self: *ComputeShaderApplication) !void {
        if (!enableValidationLayers) {
            return;
        }

        var createInfo: c.VkDebugUtilsMessengerCreateInfoEXT = undefined;
        populateDebugMessengerCreateInfo(&createInfo);
        if (createDebugUtilMessengerEXT(self.instance, &createInfo, null, &self.debugMessenger) != c.VK_SUCCESS) {
            return error.FailedToSetupDebugMessenger;
        }
    }

    fn populateDebugMessengerCreateInfo(createInfo: *c.VkDebugUtilsMessengerCreateInfoEXT) void {
        createInfo.* = .{
            .sType           = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            .messageType     = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
            .pfnUserCallback = debugCallback,
            .pUserData       = null,
        };
    }

    fn debugCallback(
        messageSeverity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
        messageType:     c.VkDebugUtilsMessageTypeFlagsEXT,
        pCallbackData:   [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
        pUserData:       ?*anyopaque,
    ) callconv(.C) c.VkBool32 {
        _, _, _ = .{&messageSeverity, &messageType, &pUserData};
        std.debug.print("validation layer: {s}\n", .{pCallbackData.*.pMessage});

        return c.VK_FALSE;
    }

    fn createSurface(self: *ComputeShaderApplication) !void {
        if (c.glfwCreateWindowSurface(self.instance, self.window, null, &self.surface) != c.VK_SUCCESS) {
            return error.FailedToCreateWindowSurface;
        }
    }

    fn pickPhysicalDevice(self: *ComputeShaderApplication) !void {
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

        if (self.physicalDevice == @as(c.VkPhysicalDevice, @ptrCast(c.VK_NULL_HANDLE))) {
            return error.FailedToFindASuitableGpu;
        }
    }

    fn isDeviceSuitable(
        device:    c.VkPhysicalDevice,
        surface:   c.VkSurfaceKHR,
        allocator: *const std.mem.Allocator,
    ) !bool {
        const familyIndices = try findQueueFamilies(device, surface, allocator);
        if (!familyIndices.isComplete()) {
            return false;
        }

        const extensionsSupported = try checkDeviceExtensionSupport(device, allocator);
        if (!extensionsSupported) {
            return false;
        }

        var swapChainSupport = try querySwapChainSupport(device, surface, allocator);
        defer swapChainSupport.deinit();
        const swapChainAdequate = swapChainSupport.formats.items.len > 0 and swapChainSupport.presentModes.items.len > 0;
        if (!swapChainAdequate) {
            return false;
        }

        return true;
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

    fn createLogicalDevice(self: *ComputeShaderApplication) !void {
        const familyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);

        var queueCreateInfos    = std.ArrayList(c.VkDeviceQueueCreateInfo).init(self.allocator.*);
        defer queueCreateInfos.deinit();

        var uniqueQueueFamilies = std.AutoHashMap(u32, void).init(self.allocator.*);
        defer uniqueQueueFamilies.deinit();
        try uniqueQueueFamilies.put(familyIndices.graphicsAndCompute.?, {});
        try uniqueQueueFamilies.put(familyIndices.present.?, {});
        try uniqueQueueFamilies.put(familyIndices.transfer.?, {});
        const queuePriority: f32 = 1.0;
        var it = uniqueQueueFamilies.iterator();
        while (it.next()) |entry| {
            const queueCreateInfo: c.VkDeviceQueueCreateInfo = .{
                .sType            = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = entry.key_ptr.*,
                .queueCount       = 1,
                .pQueuePriorities = &queuePriority,
            };
            try queueCreateInfos.append(queueCreateInfo);
        }

        var deviceFeatures: c.VkPhysicalDeviceFeatures = .{};
        const createInfo: c.VkDeviceCreateInfo = .{
            .sType                   = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount    = @intCast(queueCreateInfos.items.len),
            .pQueueCreateInfos       = queueCreateInfos.items.ptr,
            .pEnabledFeatures        = &deviceFeatures,
            .enabledExtensionCount   = @intCast(deviceExtensions.len),
            .ppEnabledExtensionNames = deviceExtensions.ptr,
        };
        if (c.vkCreateDevice(self.physicalDevice, &createInfo, null, &self.device) != c.VK_SUCCESS) {
            return error.FailedToCreateLogicalDevice;
        }

        c.vkGetDeviceQueue(self.device, familyIndices.graphicsAndCompute.?, 0, &self.graphicsQueue);
        c.vkGetDeviceQueue(self.device, familyIndices.graphicsAndCompute.?, 0, &self.computeQueue);
        c.vkGetDeviceQueue(self.device, familyIndices.present.?, 0, &self.presentQueue);
        c.vkGetDeviceQueue(self.device, familyIndices.transfer.?, 0, &self.transferQueue);
    }

    fn findQueueFamilies(device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR, allocator: *const std.mem.Allocator) !QueueFamilyIndices {
        var familyIndices: QueueFamilyIndices = .{};

        var queueFamilyCount: u32 = 0;
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
        const queueFamilies = try allocator.alloc(c.VkQueueFamilyProperties, queueFamilyCount);
        defer allocator.free(queueFamilies);
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);
        for (queueFamilies, 0..) |queueFamily, i| {
            // NOTE: The same queue family used for both drawing and presentation would yield improved performance
            // compared to this loop implementation (even though it can happen in this implementation
            // that the same queue family gets selected for both). (2025-04-19)
            // IMPORTANT: There is no fallback for when the transfer queue family is not found for familyIndices.transferFamily
            // because the tutorial task requires that transfer queue is selected from a queue family that doesn't contain the graphics queue. (2025-06-04)

            if ((queueFamily.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) != 0) {
                if ((queueFamily.queueFlags & c.VK_QUEUE_COMPUTE_BIT) != 0) {
                    familyIndices.graphicsAndCompute = @intCast(i);
                }
            } else if ((queueFamily.queueFlags & c.VK_QUEUE_TRANSFER_BIT) != 0) {
                familyIndices.transfer = @intCast(i);
            }

            var doesSupportPresent: c.VkBool32 = 0;
            _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface, &doesSupportPresent);
            if (doesSupportPresent != 0) {
                familyIndices.present= @intCast(i);
            }

            if (familyIndices.isComplete()) {
                break;
            }
        }

        return familyIndices;
    }

    fn createSwapChain(self: *ComputeShaderApplication) !void {
        const swapChainSupport = try querySwapChainSupport(self.physicalDevice, self.surface, self.allocator);
        defer swapChainSupport.deinit();

        const surfaceFormat       = chooseSwapSurfaceFormat(&swapChainSupport.formats);
        self.swapChainImageFormat = surfaceFormat.format;

        const presentMode = chooseSwapPresentMode(&swapChainSupport.presentModes);

        const extent         = chooseSwapExtent(self, &swapChainSupport.capabilities);
        self.swapChainExtent = extent;

        var imageCount: u32 = @max(3, swapChainSupport.capabilities.minImageCount + 1);
        if (swapChainSupport.capabilities.maxImageCount > 0 and imageCount > swapChainSupport.capabilities.maxImageCount) {
            imageCount = swapChainSupport.capabilities.maxImageCount;
        }

        var createInfo: c.VkSwapchainCreateInfoKHR = .{
            .sType            = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface          = self.surface,
            .minImageCount    = imageCount,
            .imageFormat      = surfaceFormat.format,
            .imageColorSpace  = surfaceFormat.colorSpace,
            .imageExtent      = extent,
            .imageArrayLayers = 1,
            .imageUsage       = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .preTransform     = swapChainSupport.capabilities.currentTransform,
            .compositeAlpha   = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode      = presentMode,
            .clipped          = c.VK_TRUE,
            .oldSwapchain     = @ptrCast(c.VK_NULL_HANDLE),
        };

        const queueFamilyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);
        if (queueFamilyIndices.graphicsAndCompute == queueFamilyIndices.present) {
            createInfo.imageSharingMode      = c.VK_SHARING_MODE_EXCLUSIVE;
        } else {
            createInfo.imageSharingMode      = c.VK_SHARING_MODE_CONCURRENT;
            createInfo.queueFamilyIndexCount = 2;
            createInfo.pQueueFamilyIndices   = &[_]u32{queueFamilyIndices.graphicsAndCompute.?, queueFamilyIndices.present.?};
        }

        if (c.vkCreateSwapchainKHR(self.device, &createInfo, null, &self.swapChain) != c.VK_SUCCESS) {
            return error.FailedToCreateSwapChain;
        }

        _ = c.vkGetSwapchainImagesKHR(self.device, self.swapChain, &imageCount, null);
        self.swapChainImages = try self.allocator.alloc(c.VkImage, imageCount);
        _ = c.vkGetSwapchainImagesKHR(self.device, self.swapChain, &imageCount, self.swapChainImages.ptr);
    }

    fn querySwapChainSupport(
        device:    c.VkPhysicalDevice,
        surface:   c.VkSurfaceKHR,
        allocator: *const std.mem.Allocator
    ) !*SwapChainSupportDetails {
        var details = try SwapChainSupportDetails.init(allocator);

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

    fn chooseSwapExtent(self: *ComputeShaderApplication, capabilities: *const c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
        if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
            return capabilities.currentExtent;
        }

        var width:  u32 = undefined;
        var height: u32 = undefined;
        c.glfwGetFramebufferSize(self.window, @ptrCast(&width), @ptrCast(&height));

        const actualExtent: c.VkExtent2D = .{
            .width  = std.math.clamp(
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

    fn createImageViews(self: *ComputeShaderApplication) !void {
        self.swapChainImageViews = try self.allocator.alloc(c.VkImageView, self.swapChainImages.len);

        for (0..self.swapChainImages.len) |i| {
        const viewInfo: c.VkImageViewCreateInfo = .{
            .sType            = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image            = self.swapChainImages[i],
            .viewType         = c.VK_IMAGE_VIEW_TYPE_2D,
            .format           = self.swapChainImageFormat,
            .components       = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask     = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel   = 0,
                .levelCount     = 1,
                .baseArrayLayer = 0,
                .layerCount     = 1
            },
        };

        if (c.vkCreateImageView(self.device, &viewInfo, null, &self.swapChainImageViews[i]) != c.VK_SUCCESS) {
            return error.FailedToCreateImageView;
        }
        }
    }

    fn createRenderPass(self: *ComputeShaderApplication) !void {
        const colorAttachment: c.VkAttachmentDescription = .{
            .format         = self.swapChainImageFormat,
            .samples        = c.VK_SAMPLE_COUNT_1_BIT,
            .loadOp         = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp        = c.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp  = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout  = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout    = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };

        const colorAttachmentRef: c.VkAttachmentReference = .{
            .attachment = 0,
            .layout     = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        const subpass: c.VkSubpassDescription = .{
            .pipelineBindPoint    = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount = 1,
            .pColorAttachments    = &colorAttachmentRef,
        };

        const dependency: c.VkSubpassDependency = .{
            .srcSubpass    = c.VK_SUBPASS_EXTERNAL,
            .dstSubpass    = 0,
            .srcStageMask  = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = 0,
            .dstStageMask  = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        };

        const renderPassInfo: c.VkRenderPassCreateInfo = .{
            .sType           = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = 1,
            .pAttachments    = &colorAttachment,
            .subpassCount    = 1,
            .pSubpasses      = &subpass,
            .dependencyCount = 1,
            .pDependencies   = &dependency,
        };

        if (c.vkCreateRenderPass(self.device, &renderPassInfo, null, &self.renderPass) != c.VK_SUCCESS) {
            return error.FailedToCreateRenderPass;
        }
    }

    fn createComputeDescriptorSetLayout(self: *ComputeShaderApplication) !void {
        const layoutBindings = [_]c.VkDescriptorSetLayoutBinding{
            .{
                .binding            = 0,
                .descriptorCount    = 1,
                .descriptorType     = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .pImmutableSamplers = null,
                .stageFlags         = c.VK_SHADER_STAGE_COMPUTE_BIT,
            },
            .{
                .binding            = 1,
                .descriptorCount    = 1,
                .descriptorType     = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .pImmutableSamplers = null,
                .stageFlags         = c.VK_SHADER_STAGE_COMPUTE_BIT,
            },
            .{
                .binding            = 2,
                .descriptorCount    = 1,
                .descriptorType     = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .pImmutableSamplers = null,
                .stageFlags         = c.VK_SHADER_STAGE_COMPUTE_BIT,
            },
        };

        const layoutInfo: c.VkDescriptorSetLayoutCreateInfo = .{
            .sType        = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = layoutBindings.len,
            .pBindings    = &layoutBindings,
        };

        if (c.vkCreateDescriptorSetLayout(self.device, &layoutInfo, null, &self.computeDescriptorSetLayout) != c.VK_SUCCESS) {
            return error.FailedToCreateDescriptorSetLayout;
        }
    }

    fn createGraphicsPipeline(self: *ComputeShaderApplication) !void {
        const vertShaderCode = try readFile("shaders/vert.spv", self.allocator);
        defer self.allocator.free(vertShaderCode);
        const fragShaderCode = try readFile("shaders/frag.spv", self.allocator);
        defer self.allocator.free(fragShaderCode);

        const vertShaderModule = try createShaderModule(self, vertShaderCode);
        defer c.vkDestroyShaderModule(self.device, vertShaderModule, null);
        const fragShaderModule = try createShaderModule(self, fragShaderCode);
        defer c.vkDestroyShaderModule(self.device, fragShaderModule, null);

        const vertShaderStageInfo: c.VkPipelineShaderStageCreateInfo = .{
            .sType  = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage  = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vertShaderModule,
            .pName  = "main",
        };
        const fragShaderStageInfo: c.VkPipelineShaderStageCreateInfo = .{
            .sType  = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage  = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = fragShaderModule,
            .pName  = "main",
        };

        const bindingDescription    = Particle.getBindingDescription();
        const attributeDescriptions = Particle.getAttributeDescriptions();
        const vertexInputInfo: c.VkPipelineVertexInputStateCreateInfo = .{
            .sType                           = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount   = 1,
            .pVertexBindingDescriptions      = &bindingDescription,
            .vertexAttributeDescriptionCount = @intCast(attributeDescriptions.len),
            .pVertexAttributeDescriptions    = attributeDescriptions.ptr,
        };

        const inputAssembly: c.VkPipelineInputAssemblyStateCreateInfo = .{
            .sType                  = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology               = c.VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
            .primitiveRestartEnable = c.VK_FALSE,
        };

        const viewportState: c.VkPipelineViewportStateCreateInfo = .{
            .sType         = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .scissorCount  = 1,
        };

        const rasterizer: c.VkPipelineRasterizationStateCreateInfo = .{
            .sType                   = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable        = c.VK_FALSE,
            .rasterizerDiscardEnable = c.VK_FALSE,
            .polygonMode             = c.VK_POLYGON_MODE_FILL,
            .cullMode                = c.VK_CULL_MODE_BACK_BIT,
            .frontFace               = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
            .depthBiasEnable         = c.VK_FALSE,
            .lineWidth               = 1.0,
        };

        const multisampling: c.VkPipelineMultisampleStateCreateInfo = .{
            .sType                = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
            .sampleShadingEnable  = c.VK_FALSE,
        };

        const colorBlendAttachment: c.VkPipelineColorBlendAttachmentState = .{
            .blendEnable         = c.VK_TRUE,
            .srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA,
            .dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .colorBlendOp        = c.VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp        = c.VK_BLEND_OP_ADD,
            .colorWriteMask      = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
        };

        const colorBlending: c.VkPipelineColorBlendStateCreateInfo = .{
            .sType           = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable   = c.VK_FALSE,
            .logicOp         = c.VK_LOGIC_OP_COPY,
            .attachmentCount = 1,
            .pAttachments    = &colorBlendAttachment,
            .blendConstants  = .{0.0, 0.0, 0.0, 0.0}
        };

        const dynamicStates = [_]c.VkDynamicState{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
        const dynamicState: c.VkPipelineDynamicStateCreateInfo = .{
            .sType             = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynamicStates.len,
            .pDynamicStates    = &dynamicStates,
        };

        const pipelineLayoutInfo: c.VkPipelineLayoutCreateInfo = .{
            .sType          = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 0,
            .pSetLayouts    = null,
        };
        if (c.vkCreatePipelineLayout(self.device, &pipelineLayoutInfo, null, &self.pipelineLayout) != c.VK_SUCCESS) {
            return error.FailedToCreateGraphicsPipelineLayout;
        }

        const shaderStages = [_]c.VkPipelineShaderStageCreateInfo{vertShaderStageInfo, fragShaderStageInfo};
        const pipelineInfo: c.VkGraphicsPipelineCreateInfo = .{
            .sType               = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount          = 2,
            .pStages             = &shaderStages,
            .pVertexInputState   = &vertexInputInfo,
            .pInputAssemblyState = &inputAssembly,
            .pViewportState      = &viewportState,
            .pRasterizationState = &rasterizer,
            .pMultisampleState   = &multisampling,
            .pColorBlendState    = &colorBlending,
            .pDynamicState       = &dynamicState,
            .layout              = self.pipelineLayout,
            .renderPass          = self.renderPass,
            .subpass             = 0,
            .basePipelineHandle  = @ptrCast(c.VK_NULL_HANDLE)
        };

        if (c.vkCreateGraphicsPipelines(self.device, @ptrCast(c.VK_NULL_HANDLE), 1, &pipelineInfo, null, &self.graphicsPipeline) != c.VK_SUCCESS) {
            return error.FailedToCreateGraphicsPipeline;
        }
    }

    fn createShaderModule(self: *ComputeShaderApplication, code: []u8) !c.VkShaderModule {
        const createInfo: c.VkShaderModuleCreateInfo = .{
            .sType    = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = code.len,
            .pCode    = @alignCast(@ptrCast(code.ptr)),
        };

        var shaderModule: c.VkShaderModule = undefined;
        if (c.vkCreateShaderModule(self.device, &createInfo, null, &shaderModule) != c.VK_SUCCESS){
            return error.FailedToCreateShaderModule;
        }

        return shaderModule;
    }

    fn readFile(fileName: []const u8, allocator: *const std.mem.Allocator) ![]u8 {
        const file = try std.fs.cwd().openFile(fileName, .{});
        defer file.close();

        const stat   = try file.stat();
        const buffer = try file.readToEndAlloc(allocator.*, stat.size);

        return buffer;
    }

    fn createComputePipeline(self: *ComputeShaderApplication) !void {
        const computeShaderCode = try readFile("shaders/comp.spv", self.allocator);
        defer self.allocator.free(computeShaderCode);

        const computeShaderModule = try createShaderModule(self, computeShaderCode);
        defer c.vkDestroyShaderModule(self.device, computeShaderModule, null);

        const computeShaderStageInfo: c.VkPipelineShaderStageCreateInfo = .{
            .sType  = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage  = c.VK_SHADER_STAGE_COMPUTE_BIT,
            .module = computeShaderModule,
            .pName  = "main",
        };

        const pipelineLayoutInfo: c.VkPipelineLayoutCreateInfo = .{
            .sType          = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 1,
            .pSetLayouts    = &self.computeDescriptorSetLayout,
        };

        if (c.vkCreatePipelineLayout(self.device, &pipelineLayoutInfo, null, &self.computePipelineLayout) != c.VK_SUCCESS) {
            return error.FailedToCreateComputePipelineLayout;
        }

        const pipelineCreateInfo: c.VkComputePipelineCreateInfo = .{
            .sType  = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
            .layout = self.computePipelineLayout,
            .stage  = computeShaderStageInfo,
        };

        if (c.vkCreateComputePipelines(self.device, @ptrCast(c.VK_NULL_HANDLE), 1, &pipelineCreateInfo, null, &self.computePipeline) != c.VK_SUCCESS) {
            return error.FailedToCreateComputePipeline;
        }
    }

    fn createFramebuffers(self: *ComputeShaderApplication) !void {
        self.swapChainFramebuffers = try self.allocator.alloc(c.VkFramebuffer, self.swapChainImageViews.len);

        for (0..self.swapChainImageViews.len) |i| {
            const attachments = [_]c.VkImageView{self.swapChainImageViews[i]};
            const frameBufferInfo: c.VkFramebufferCreateInfo = .{
                .sType           = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass      = self.renderPass,
                .attachmentCount = attachments.len,
                .pAttachments    = &attachments,
                .width           = self.swapChainExtent.width,
                .height          = self.swapChainExtent.height,
                .layers          = 1,
            };

            if (c.vkCreateFramebuffer(self.device, &frameBufferInfo, null, &self.swapChainFramebuffers[i]) != c.VK_SUCCESS) {
                return error.FailedToCreateFramebuffer;
            }
        }
    }

    fn createCommandPool(self: *ComputeShaderApplication) !void {
        const queueFamilyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);

        const graphicsAndComputePoolInfo: c.VkCommandPoolCreateInfo = .{
            .sType            = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags            = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queueFamilyIndices.graphicsAndCompute.?,
        };
        if (c.vkCreateCommandPool(self.device, &graphicsAndComputePoolInfo, null, &self.graphicsAndComputeCommandPool) != c.VK_SUCCESS) {
            return error.FailedToCreateGraphicsCommandPool;
        }

        const transferPoolInfo: c.VkCommandPoolCreateInfo = .{
            .sType            = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags            = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queueFamilyIndices.transfer.?,
        };
        if (c.vkCreateCommandPool(self.device, &transferPoolInfo, null, &self.transferCommandPool) != c.VK_SUCCESS) {
            return error.FailedToCreateTransferCommandPool;
        }
    }

    fn createShaderStorageBuffers(self: *ComputeShaderApplication) !void {
        var prng     = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
        const random = prng.random();

        // Initial particle positions on a circle
        var particles: [PARTICLE_COUNT]Particle = undefined;
        for (0..particles.len) |i| {
            const r:     f32 = 0.25 * @sqrt(random.float(f32));
            const theta: f32 = random.float(f32) * 2.0 * 3.14159265358979323846;
            const x:     f32 = r * @cos(theta) * HEIGHT / WIDTH;
            const y:     f32 = r * @sin(theta);
            particles[i].position = .{x, y};
            particles[i].velocity = blk: {
                var tmp = c.vec2{x, y};
                c.glm_vec2_scale_as(&tmp, 0.00025, &tmp);
                break :blk tmp;
            };
            particles[i].color    = .{random.float(f32), random.float(f32), random.float(f32), 1.0};
        }

        const bufferSize: c.VkDeviceSize = @sizeOf(Particle) * PARTICLE_COUNT;

        // Create a staging buffer used to upload data to the gpu
        var stagingBuffer:       c.VkBuffer       = undefined;
        var stagingBufferMemory: c.VkDeviceMemory = undefined;
        try createBuffer(
            self,
            bufferSize,
            c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &stagingBuffer,
            &stagingBufferMemory,
        );
        defer c.vkDestroyBuffer(self.device, stagingBuffer, null);
        defer c.vkFreeMemory(self.device, stagingBufferMemory, null);

        var data: [*]Particle = undefined;
        _ = c.vkMapMemory(self.device, stagingBufferMemory, 0, bufferSize, 0, @ptrCast(&data));
        @memcpy(data, &particles);
        c.vkUnmapMemory(self.device, stagingBufferMemory);

        // Copy initial particle data to all storage buffers
        for (0..self.shaderStorageBuffers.len) |i| {
            try createBuffer(
                self,
                bufferSize,
                c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                &self.shaderStorageBuffers[i],
                &self.shaderStorageBuffersMemory[i],
            );
            copyBuffer(self, stagingBuffer, self.shaderStorageBuffers[i], bufferSize);
        }
    }

    fn createBuffer(
        self:         *ComputeShaderApplication,
        size:         c.VkDeviceSize,
        usage:        c.VkBufferUsageFlags,
        properties:   c.VkMemoryPropertyFlags,
        buffer:       *c.VkBuffer,
        bufferMemory: *c.VkDeviceMemory,
    ) !void {
        const familyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);

        const bufferInfo: c.VkBufferCreateInfo = .{
            .sType                 = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size                  = size,
            .usage                 = usage,
            .sharingMode           = c.VK_SHARING_MODE_CONCURRENT,
            .queueFamilyIndexCount = 2,
            .pQueueFamilyIndices   = &[_]u32{familyIndices.graphicsAndCompute.?, familyIndices.transfer.?},
        };
        if (c.vkCreateBuffer(self.device, &bufferInfo, null, buffer) != c.VK_SUCCESS) {
            return error.FailedToCreateBuffer;
        }

        var memRequirements: c.VkMemoryRequirements = undefined;
        c.vkGetBufferMemoryRequirements(self.device, buffer.*, &memRequirements);

        const allocInfo: c.VkMemoryAllocateInfo = .{
            .sType           = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize  = memRequirements.size,
            .memoryTypeIndex = try self.findMemoryType(memRequirements.memoryTypeBits, properties),
        };
        if (c.vkAllocateMemory(self.device, &allocInfo, null, bufferMemory) != c.VK_SUCCESS) {
            return error.FailedToAllocateVertexBufferMemory;
        }

        _ = c.vkBindBufferMemory(self.device, buffer.*, bufferMemory.*, 0);
    }

    fn findMemoryType(self: *ComputeShaderApplication, typeFilter: u32, properties: c.VkMemoryPropertyFlags) !u32 {
        var memProperties: c.VkPhysicalDeviceMemoryProperties = undefined;
        c.vkGetPhysicalDeviceMemoryProperties(self.physicalDevice, &memProperties);

        for (0..memProperties.memoryTypeCount) |i| {
            const bit = @as(u32, 1) << @intCast(i);
            if (typeFilter & bit != 0 and (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
                return @intCast(i);
            }
        }
        return error.FailedToFindSuitableMemoryType;
    }

    fn copyBuffer(self: *ComputeShaderApplication, srcBuffer: c.VkBuffer, dstBuffer: c.VkBuffer, size: c.VkDeviceSize) void {
        const allocInfo: c.VkCommandBufferAllocateInfo = .{
            .sType              = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .level              = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandPool        = self.transferCommandPool,
            .commandBufferCount = 1,
        };
        var commandBuffer: c.VkCommandBuffer = undefined;
        _ = c.vkAllocateCommandBuffers(self.device, &allocInfo, &commandBuffer);

        const beginInfo: c.VkCommandBufferBeginInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };
        _ = c.vkBeginCommandBuffer(commandBuffer, &beginInfo);

        var copyRegion: c.VkBufferCopy = .{
            .srcOffset = 0, // Optional
            .dstOffset = 0, // Optional
            .size      = size,
        };
        c.vkCmdCopyBuffer(commandBuffer, srcBuffer, dstBuffer, 1, &copyRegion);

        _ = c.vkEndCommandBuffer(commandBuffer);

        const submitInfo: c.VkSubmitInfo = .{
            .sType              = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers    = &commandBuffer,
        };
        _ = c.vkQueueSubmit(self.graphicsQueue, 1, &submitInfo, @ptrCast(c.VK_NULL_HANDLE));

        _ = c.vkQueueWaitIdle(self.graphicsQueue);

        c.vkFreeCommandBuffers(self.device, self.transferCommandPool, 1, &commandBuffer);
    }

    fn createUniformBuffers(self: *ComputeShaderApplication) !void {
        const bufferSize: c.VkDeviceSize = @sizeOf(UniformBufferObject);

        for (0..self.uniformBuffers.len) |i| {
            try createBuffer(
                self,
                bufferSize,
                c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                &self.uniformBuffers[i],
                &self.uniformBuffersMemory[i],
            );
            _ = c.vkMapMemory(self.device, self.uniformBuffersMemory[i], 0, bufferSize, 0, @ptrCast(&self.uniformBuffersMapped[i]));
        }
    }

    fn createDescriptorPool(self: *ComputeShaderApplication) !void  {
        const poolSizes = [_]c.VkDescriptorPoolSize{
            .{
                .type            = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = MAX_FRAMES_IN_FLIGHT,
            },
            .{
                .type            = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                .descriptorCount = MAX_FRAMES_IN_FLIGHT * 2,
            },
        };

        const poolInfo: c.VkDescriptorPoolCreateInfo = .{
            .sType         = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .poolSizeCount = poolSizes.len,
            .pPoolSizes    = &poolSizes,
            .maxSets       = MAX_FRAMES_IN_FLIGHT,
        };

        if (c.vkCreateDescriptorPool(self.device, &poolInfo, null, &self.descriptorPool) != c.VK_SUCCESS) {
            return error.FailedToCreateDescriptorPool;
        }
    }

    fn createComputeDescriptorSets(self: *ComputeShaderApplication) !void {
        var layouts = [_]c.VkDescriptorSetLayout{self.computeDescriptorSetLayout} ** MAX_FRAMES_IN_FLIGHT;
        const allocInfo: c.VkDescriptorSetAllocateInfo = .{
            .sType              = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool     = self.descriptorPool,
            .descriptorSetCount = layouts.len,
            .pSetLayouts        = &layouts,
        };
        if (c.vkAllocateDescriptorSets(self.device, &allocInfo, &self.computeDescriptorSets) != c.VK_SUCCESS) {
            return error.FailedToAllocateDescriptorSets;
        }

        for (0..self.computeDescriptorSets.len) |i| {
            const uniformBufferInfo:             c.VkDescriptorBufferInfo = .{
                .buffer = self.uniformBuffers[i],
                .offset = 0,
                .range  = @sizeOf(UniformBufferObject),
            };
            const storageBufferInfoLastFrame:    c.VkDescriptorBufferInfo = .{
                .buffer = self.shaderStorageBuffers[@intCast(@mod((@as(isize, @intCast(i)) - 1), MAX_FRAMES_IN_FLIGHT))],
                .offset = 0,
                .range  = @sizeOf(Particle) * PARTICLE_COUNT,
            };
            const storageBufferInfoCurrentFrame: c.VkDescriptorBufferInfo = .{
                .buffer = self.shaderStorageBuffers[i],
                .offset = 0,
                .range  = @sizeOf(Particle) * PARTICLE_COUNT,
            };

            var descriptorWrites = [_]c.VkWriteDescriptorSet{
                .{
                    .sType           = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .dstSet          = self.computeDescriptorSets[i],
                    .dstBinding      = 0,
                    .dstArrayElement = 0,
                    .descriptorType  = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .descriptorCount = 1,
                    .pBufferInfo     = &uniformBufferInfo,
                },
                .{
                    .sType           = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .dstSet          = self.computeDescriptorSets[i],
                    .dstBinding      = 1,
                    .dstArrayElement = 0,
                    .descriptorType  = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                    .descriptorCount = 1,
                    .pBufferInfo     = &storageBufferInfoLastFrame,
                },
                .{
                    .sType           = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .dstSet          = self.computeDescriptorSets[i],
                    .dstBinding      = 2,
                    .dstArrayElement = 0,
                    .descriptorType  = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                    .descriptorCount = 1,
                    .pBufferInfo     = &storageBufferInfoCurrentFrame,
                }
            };

            c.vkUpdateDescriptorSets(self.device, descriptorWrites.len, &descriptorWrites, 0, null);
        }
    }

    fn createCommandBuffers(self: *ComputeShaderApplication) !void {
        const allocInfo: c.VkCommandBufferAllocateInfo = .{
            .sType              = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool        = self.graphicsAndComputeCommandPool,
            .level              = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = self.commandBuffers.len,
        };

        if (c.vkAllocateCommandBuffers(self.device, &allocInfo, &self.commandBuffers) != c.VK_SUCCESS) {
            return error.FailedToAllocateCommandBuffers;
        }
    }

    fn createComputeCommandBuffers(self: *ComputeShaderApplication) !void {
        const allocInfo: c.VkCommandBufferAllocateInfo = .{
            .sType              = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool        = self.graphicsAndComputeCommandPool,
            .level              = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = self.computeCommandBuffers.len,
        };

        if (c.vkAllocateCommandBuffers(self.device, &allocInfo, &self.computeCommandBuffers) != c.VK_SUCCESS) {
            return error.FailedToAllocateComputeCommandBuffers;
        }
    }

    fn createSyncObjects(self: *ComputeShaderApplication) !void {
        const semaphoreInfo: c.VkSemaphoreCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        const fenceInfo: c.VkFenceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            if (c.vkCreateSemaphore(self.device, &semaphoreInfo, null, &self.imageAvailableSemaphores[i]) != c.VK_SUCCESS
                or c.vkCreateSemaphore(self.device, &semaphoreInfo, null, &self.renderFinishedSemaphores[i]) != c.VK_SUCCESS
                or c.vkCreateFence(self.device, &fenceInfo, null, &self.inFlightFences[i]) != c.VK_SUCCESS) {
                return error.FailedToCreateGraphicsSynchronizationObjectsForAFrame;
            }

            if ((c.vkCreateSemaphore(self.device, &semaphoreInfo, null, &self.computeFinishedSemaphores[i]) != c.VK_SUCCESS)
                or (c.vkCreateFence(self.device, &fenceInfo, null, &self.computeInFlightFences[i]) != c.VK_SUCCESS)) {
                return error.FailedToCreateComputeSynchronizationObjectsForAFrame;
            }
        }
    }

    fn drawFrame(self: *ComputeShaderApplication) !void {
        // Compute submission
        _ = c.vkWaitForFences(self.device, 1, &self.computeInFlightFences[self.currentFrame], c.VK_TRUE, c.UINT64_MAX);

        self.updateUniformBuffer(self.currentFrame);

        _ = c.vkResetFences(self.device, 1, &self.computeInFlightFences[self.currentFrame]);

        _ = c.vkResetCommandBuffer(self.computeCommandBuffers[self.currentFrame], 0);
        try self.recordComputeCommandBuffer(self.computeCommandBuffers[self.currentFrame]);

        var submitInfo: c.VkSubmitInfo = .{
            .sType                = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount   = 1,
            .pCommandBuffers      = &self.computeCommandBuffers[self.currentFrame],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores    = &self.computeFinishedSemaphores[self.currentFrame],
        };

        if (c.vkQueueSubmit(self.computeQueue, 1, &submitInfo, self.computeInFlightFences[self.currentFrame]) != c.VK_SUCCESS) {
            return error.FailedToSubmitComputeCommandBuffer;
        }

        // Graphics submission
        _ = c.vkWaitForFences(self.device, 1, &self.inFlightFences[self.currentFrame], c.VK_TRUE, c.UINT64_MAX);

        var imageIndex: u32 = undefined;
        var result = c.vkAcquireNextImageKHR(self.device, self.swapChain, c.UINT64_MAX, self.imageAvailableSemaphores[self.currentFrame], @ptrCast(c.VK_NULL_HANDLE), &imageIndex);
        if (result == c.VK_ERROR_OUT_OF_DATE_KHR) {
            try self.recreateSwapChain();
            return;
        } else if (result != c.VK_SUCCESS and result != c.VK_SUBOPTIMAL_KHR) {
            return error.FailedToAcquireSwapChainImage;
        }

        _ = c.vkResetFences(self.device, 1, &self.inFlightFences[self.currentFrame]);

        _ = c.vkResetCommandBuffer(self.commandBuffers[self.currentFrame], 0);
        try self.recordCommandBuffer(self.commandBuffers[self.currentFrame], imageIndex);

        const waitSemaphores = [_]c.VkSemaphore{
            self.computeFinishedSemaphores[self.currentFrame],
            self.imageAvailableSemaphores[self.currentFrame],
        };
        const waitStages = [_]c.VkPipelineStageFlags{
            c.VK_PIPELINE_STAGE_VERTEX_INPUT_BIT,
            c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
        };
        submitInfo = .{
            .sType                = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount   = 2,
            .pWaitSemaphores      = &waitSemaphores,
            .pWaitDstStageMask    = &waitStages,
            .commandBufferCount   = 1,
            .pCommandBuffers      = &self.commandBuffers[self.currentFrame],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores    = &self.renderFinishedSemaphores[self.currentFrame],
        };

        if (c.vkQueueSubmit(self.graphicsQueue, 1, &submitInfo, self.inFlightFences[self.currentFrame]) != c.VK_SUCCESS) {
            return error.FailedToSubmitDrawCommandBuffer;
        }

        const swapChains = [_]c.VkSwapchainKHR{self.swapChain};
        const presentInfo: c.VkPresentInfoKHR = .{
            .sType              = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores    = &self.renderFinishedSemaphores[self.currentFrame],
            .swapchainCount     = 1,
            .pSwapchains        = &swapChains,
            .pImageIndices      = &imageIndex,
        };

        result = c.vkQueuePresentKHR(self.presentQueue, &presentInfo);
        if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or self.framebufferResized) {
            self.framebufferResized = false;
            try self.recreateSwapChain();
        } else if (result != c.VK_SUCCESS) {
            return error.FailedToAcquireSwapChainImage;
        }

        self.currentFrame = (self.currentFrame + 1) % MAX_FRAMES_IN_FLIGHT;
    }

    fn updateUniformBuffer(self: *ComputeShaderApplication, currentImage: u32) void {
        self.uniformBuffersMapped[currentImage].* = .{.deltaTime = self.lastFrameTime * 2.0};
    }

    fn recordComputeCommandBuffer(self: *ComputeShaderApplication, commandBuffer: c.VkCommandBuffer) !void {
        const beginInfo: c.VkCommandBufferBeginInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        };

        if (c.vkBeginCommandBuffer(commandBuffer, &beginInfo) != c.VK_SUCCESS) {
            return error.FailedToBeginRecordingComputeCommandBuffer;
        }

        c.vkCmdBindPipeline(commandBuffer, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.computePipeline);

        c.vkCmdBindDescriptorSets(commandBuffer, c.VK_PIPELINE_BIND_POINT_COMPUTE, self.computePipelineLayout, 0, 1, &self.computeDescriptorSets[self.currentFrame], 0, null);

        c.vkCmdDispatch(commandBuffer, PARTICLE_COUNT / 256, 1, 1);

        if (c.vkEndCommandBuffer(commandBuffer) != c.VK_SUCCESS) {
            return error.FailedToRecordComputeCommandBuffer;
        }
    }

    fn recordCommandBuffer(
        self:          *ComputeShaderApplication,
        commandBuffer: c.VkCommandBuffer,
        imageIndex:    u32,
    ) !void {
        const beginInfo: c.VkCommandBufferBeginInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        };

        if (c.vkBeginCommandBuffer(commandBuffer, &beginInfo) != c.VK_SUCCESS) {
            return error.FailedToBeginRecordingCommandBuffer;
        }

        const clearColor: c.VkClearValue = .{.color = .{.float32 = .{0.0, 0.0, 0.0, 1.0}}};
        const renderPassInfo: c.VkRenderPassBeginInfo = .{
            .sType           = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass      = self.renderPass,
            .framebuffer     = self.swapChainFramebuffers[imageIndex],
            .renderArea      = .{
                .offset = .{.x = 0.0, .y = 0.0},
                .extent = self.swapChainExtent,
            },
            .clearValueCount = 1,
            .pClearValues    = &clearColor,
        };

        c.vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, c.VK_SUBPASS_CONTENTS_INLINE);

        c.vkCmdBindPipeline(commandBuffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.graphicsPipeline);
        const viewPort: c.VkViewport = .{
            .x        = 0.0,
            .y        = 0.0,
            .width    = @floatFromInt(self.swapChainExtent.width),
            .height   = @floatFromInt(self.swapChainExtent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0
        };
        c.vkCmdSetViewport(commandBuffer, 0, 1, &viewPort);

        const scissor: c.VkRect2D = .{
            .offset = .{.x = 0.0, .y = 0.0},
            .extent = self.swapChainExtent,
        };
        c.vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

        const offsets = [_]c.VkDeviceSize{0};
        c.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &self.shaderStorageBuffers[self.currentFrame], &offsets);

        c.vkCmdDraw(commandBuffer, PARTICLE_COUNT, 1, 0, 0);

        c.vkCmdEndRenderPass(commandBuffer);

        if (c.vkEndCommandBuffer(commandBuffer) != c.VK_SUCCESS) {
            return error.FailedToRecordCommandBuffer;
        }
    }

    fn recreateSwapChain(self: *ComputeShaderApplication) !void {
        var width: c_int, var height: c_int = .{0, 0};
        c.glfwGetFramebufferSize(self.window, &width, &height);
        while (width == 0 or height == 0) {
            c.glfwGetFramebufferSize(self.window, &width, &height);
            c.glfwWaitEvents();
        }

        _ = c.vkDeviceWaitIdle(self.device);

        self.cleanupSwapChain();

        try self.createSwapChain();
        try self.createImageViews();
        try self.createFramebuffers();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app: ComputeShaderApplication = .{ .allocator = &allocator };

    try app.run();
}
