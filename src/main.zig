const c = @cImport({
    @cInclude("stb_image.h");
});
const vk      = @import("bindings/vulkan.zig").vk;
const glfwLib = @import("bindings/glfw.zig");
const glfw    = glfwLib.glfw;
const cglm    = @import("bindings/cglm.zig").cglm;

const std         = @import("std");
const builtin     = @import("builtin");
const ModelLoader = @import("model-loader.zig");
const Vertex      = @import("vertex.zig").Vertex;

const WIDTH:                u32 = 800;
const HEIGHT:               u32 = 600;
const MAX_FRAMES_IN_FLIGHT: u32 = 2;

const MODEL_PATH   = "models/viking_room.obj";
const TEXTURE_PATH = "textures/viking_room.png";

const validationLayers       = &[_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
const enableValidationLayers = builtin.mode == .Debug;

const deviceExtensions       = &[_][*c]const u8{vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

fn createDebugUtilMessengerEXT(
    instance:        vk.VkInstance,
    pCreateInfo:     *vk.VkDebugUtilsMessengerCreateInfoEXT,
    pAllocator:      ?*const vk.VkAllocationCallbacks,
    pDebugMessenger: *vk.VkDebugUtilsMessengerEXT,
) vk.VkResult {
    const func: vk.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(vk.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
    if (func) |f| {
        return f(instance, pCreateInfo, pAllocator, pDebugMessenger);
    } else {
        return vk.VK_ERROR_EXTENSION_NOT_PRESENT;
    }
}

fn DestroyDebugUtilsMessengerEXT(
    instance:       vk.VkInstance,
    debugMessenger: vk.VkDebugUtilsMessengerEXT,
    pAllocator:     ?*const vk.VkAllocationCallbacks,
) void {
    const func: vk.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(vk.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
    if (func) |f| {
        f(instance, debugMessenger, pAllocator);
    }
}

const QueueFamilyIndices = struct {
    graphicsFamily: ?u32,
    presentFamily:  ?u32,
    transferFamily: ?u32,

    fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphicsFamily != null and self.presentFamily != null and self.transferFamily != null;
    }
};

const SwapChainSupportDetails = struct {
    capabilities: vk.VkSurfaceCapabilitiesKHR,
    formats:      std.ArrayList(vk.VkSurfaceFormatKHR),
    presentModes: std.ArrayList(vk.VkPresentModeKHR),
    allocator:    *const std.mem.Allocator,

    fn init(allocator: *const std.mem.Allocator) !*SwapChainSupportDetails {
        const details        = try allocator.create(SwapChainSupportDetails);
        details.capabilities = undefined;
        details.formats      = std.ArrayList(vk.VkSurfaceFormatKHR).init(allocator.*);
        details.presentModes = std.ArrayList(vk.VkPresentModeKHR).init(allocator.*);
        details.allocator    = allocator;

        return details;
    }

    fn deinit(self: *SwapChainSupportDetails) void {
        self.formats.deinit();
        self.formats      = undefined;
        self.presentModes.deinit();
        self.presentModes = undefined;

        self.allocator.destroy(self);
    }
};


const UniformBufferObject  = struct {
    model: cglm.mat4 align(16) = undefined,
    view:  cglm.mat4 align(16) = undefined,
    proj:  cglm.mat4 align(16) = undefined,
};

const HelloTriangleApplication = struct {
    window:  ?*glfw.GLFWwindow = undefined,
    surface: vk.VkSurfaceKHR   = undefined,

    swapChain:            vk.VkSwapchainKHR = undefined,
    swapChainImages:      []vk.VkImage      = undefined,
    swapChainImageFormat: vk.VkFormat       = undefined,
    swapChainExtent:      vk.VkExtent2D     = undefined,
    swapChainImageViews:  []vk.VkImageView  = undefined,

    instance:       vk.VkInstance               = undefined,
    debugMessenger: vk.VkDebugUtilsMessengerEXT = undefined,

    physicalDevice: vk.VkPhysicalDevice = @ptrCast(vk.VK_NULL_HANDLE),
    device:         vk.VkDevice         = undefined,

    graphicsQueue:  vk.VkQueue = undefined,
    presentQueue:   vk.VkQueue = undefined,
    transferQueue:  vk.VkQueue = undefined,

    renderPass:          vk.VkRenderPass          = undefined,
    descriptorSetLayout: vk.VkDescriptorSetLayout = undefined,
    pipelineLayout:      vk.VkPipelineLayout      = undefined,
    graphicsPipeline:    vk.VkPipeline            = undefined,

    depthImage:       vk.VkImage        = undefined,
    depthImageMemory: vk.VkDeviceMemory = undefined,
    depthImageView:   vk.VkImageView    = undefined,

    swapChainFramebuffers: []vk.VkFramebuffer = undefined,

    graphicsCommandPool:    vk.VkCommandPool                         = undefined,
    transferCommandPool:    vk.VkCommandPool                         = undefined,
    graphicsCommandBuffers: [MAX_FRAMES_IN_FLIGHT]vk.VkCommandBuffer = undefined,
    transferCommandBuffers: [MAX_FRAMES_IN_FLIGHT]vk.VkCommandBuffer = undefined,

    textureImage:       vk.VkImage        = undefined,
    textureImageMemory: vk.VkDeviceMemory = undefined,
    textureImageView:   vk.VkImageView    = undefined,
    textureSampler:     vk.VkSampler      = undefined,

    vertices:           std.ArrayList(Vertex) = undefined,
    indices:            std.ArrayList(u32)    = undefined,
    vertexBuffer:       vk.VkBuffer            = undefined,
    indexBuffer:        vk.VkBuffer            = undefined,
    vertexBufferMemory: vk.VkDeviceMemory      = undefined,
    indexBufferMemory:  vk.VkDeviceMemory      = undefined,

    uniformBuffers:       [MAX_FRAMES_IN_FLIGHT]vk.VkBuffer           = undefined,
    uniformBuffersMemory: [MAX_FRAMES_IN_FLIGHT]vk.VkDeviceMemory     = undefined,
    uniformBuffersMapped: [MAX_FRAMES_IN_FLIGHT]*UniformBufferObject  = undefined,

    descriptorPool: vk.VkDescriptorPool                      = undefined,
    descriptorSets: [MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSet = undefined,

    imageAvailableSemaphores: [MAX_FRAMES_IN_FLIGHT]vk.VkSemaphore = undefined,
    renderFinishedSemaphores: [MAX_FRAMES_IN_FLIGHT]vk.VkSemaphore = undefined,
    inFlightFences:           [MAX_FRAMES_IN_FLIGHT]vk.VkFence     = undefined,
    currentFrame:             u32                                  = 0,

    framebufferResized: bool = false,

    startTime: i64,

    allocator: *const std.mem.Allocator,

    pub fn run(self: *HelloTriangleApplication) !void {
        try self.initWindow();
        try self.initVulkan();
        try self.mainLoop();
        try self.cleanup();
    }

    fn initWindow(self: *HelloTriangleApplication) !void {
        if (glfw.glfwInit() == glfw.GLFW_FALSE) {
            return error.FailedGlfwInitialization;
        }

        glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);
        //glfw.glfwWindowHint(glfw.GLFW_RESIZABLE, glfw.GLFW_FALSE);

        self.window = glfw.glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", null, null);
        glfw.glfwSetWindowUserPointer(self.window, self);
        _ = glfw.glfwSetFramebufferSizeCallback(self.window, framebufferResizeCallback);
    }

    fn framebufferResizeCallback(window: ?*glfw.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
        _, _ = .{width, height};
        const app: ?*HelloTriangleApplication = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(window)));
        app.?.framebufferResized = true;
    }

    fn initVulkan(self: *HelloTriangleApplication) !void {
        try self.createInstance();
        try self.setupDebugMessenger();
        try self.createSurface();
        try self.pickPhysicalDevice();
        try self.createLogicalDevice();
        try self.createSwapChain();
        try self.createImageViews();
        try self.createRenderPass();
        try self.createDescriptorSetLayout();
        try self.createGraphicsPipeline();
        try self.createCommandPool();
        try self.createDepthResources();
        try self.createFramebuffers();
        try self.createTextureImage();
        try self.createTextureImageView();
        try self.createTextureSampler();
        try self.loadModel();
        try self.createVertexBuffer();
        try self.createIndexBuffer();
        try self.createUniformBuffers();
        try self.createDescriptorPool();
        try self.createDescriptorSets();
        try self.createCommandBuffers();
        try self.createSyncObjects();
    }

    fn mainLoop(self: *HelloTriangleApplication) !void {
        while (glfw.glfwWindowShouldClose(self.window.?) == 0) {
            glfw.glfwPollEvents();
            try self.drawFrame();
        }

        _ = vk.vkDeviceWaitIdle(self.device);
    }

    fn cleanup(self: *HelloTriangleApplication) !void {
        self.vertices.deinit();
        self.indices.deinit();

        self.cleanupSwapChain();

        vk.vkDestroySampler(self.device, self.textureSampler, null);
        vk.vkDestroyImageView(self.device, self.textureImageView, null);

        vk.vkDestroyImage(self.device, self.textureImage, null);
        vk.vkFreeMemory(self.device, self.textureImageMemory, null);

        vk.vkDestroyPipeline(self.device, self.graphicsPipeline, null);
        vk.vkDestroyPipelineLayout(self.device, self.pipelineLayout, null);
        vk.vkDestroyRenderPass(self.device, self.renderPass, null);

        for (0..self.uniformBuffers.len) |i| {
            vk.vkDestroyBuffer(self.device, self.uniformBuffers[i], null);
            vk.vkFreeMemory(self.device, self.uniformBuffersMemory[i], null);
        }

        vk.vkDestroyDescriptorPool(self.device, self.descriptorPool, null);

        vk.vkDestroyDescriptorSetLayout(self.device, self.descriptorSetLayout, null);

        vk.vkDestroyBuffer(self.device, self.vertexBuffer, null);
        vk.vkFreeMemory(self.device, self.vertexBufferMemory, null);

        vk.vkDestroyBuffer(self.device, self.indexBuffer, null);
        vk.vkFreeMemory(self.device, self.indexBufferMemory, null);

        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            vk.vkDestroySemaphore(self.device, self.imageAvailableSemaphores[i], null);
            vk.vkDestroySemaphore(self.device, self.renderFinishedSemaphores[i], null);
            vk.vkDestroyFence(self.device, self.inFlightFences[i], null);
        }

        vk.vkDestroyCommandPool(self.device, self.graphicsCommandPool, null);
        vk.vkDestroyCommandPool(self.device, self.transferCommandPool, null);

        vk.vkDestroyDevice(self.device, null);

        if (enableValidationLayers) {
            DestroyDebugUtilsMessengerEXT(self.instance, self.debugMessenger, null);
        }

        vk.vkDestroySurfaceKHR(self.instance, self.surface, null);
        vk.vkDestroyInstance(self.instance, null);

        glfw.glfwDestroyWindow(self.window);

        glfw.glfwTerminate();
    }

    fn cleanupSwapChain(self: *HelloTriangleApplication) void {
        vk.vkDestroyImageView(self.device, self.depthImageView, null);
        vk.vkDestroyImage(self.device, self.depthImage, null);
        vk.vkFreeMemory(self.device, self.depthImageMemory, null);

        for (self.swapChainFramebuffers) |framebuffer| {
            vk.vkDestroyFramebuffer(self.device, framebuffer, null);
        }
        self.allocator.free(self.swapChainFramebuffers);

        for (self.swapChainImageViews) |imageView| {
            vk.vkDestroyImageView(self.device, imageView, null);
        }
        self.allocator.free(self.swapChainImageViews);

        vk.vkDestroySwapchainKHR(self.device, self.swapChain, null);
        self.allocator.free(self.swapChainImages);
    }

    fn recreateSwapChain(self: *HelloTriangleApplication) !void {
        var width: c_int, var height: c_int = .{0, 0};
        glfw.glfwGetFramebufferSize(self.window, &width, &height);
        while (width == 0 or height == 0) {
            glfw.glfwGetFramebufferSize(self.window, &width, &height);
            glfw.glfwWaitEvents();
        }

        _ = vk.vkDeviceWaitIdle(self.device);

        self.cleanupSwapChain();

        try self.createSwapChain();
        try self.createImageViews();
        try self.createDepthResources();
        try self.createFramebuffers();
    }

    fn createInstance(self: *HelloTriangleApplication) !void {
        if (enableValidationLayers and !(try checkValidationLayerSupport(self.allocator))) {
            return error.ValidationLayersNotFound;
        }

        const appInfo: vk.VkApplicationInfo = .{
            .sType              = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName   = "Hello Triangle",
            .applicationVersion = vk.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName        = "No Engine",
            .engineVersion      = vk.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion         = vk.VK_API_VERSION_1_0,
        };

        const extensions = try getRequiredExtensions(self.allocator);
        defer extensions.deinit();
        var createInfo: vk.VkInstanceCreateInfo = .{};
        createInfo.sType                   = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        createInfo.pApplicationInfo        = &appInfo;
        createInfo.enabledExtensionCount   = @intCast(extensions.items.len);
        createInfo.ppEnabledExtensionNames = extensions.items.ptr;
        var debugCreateInfo: vk.VkDebugUtilsMessengerCreateInfoEXT = undefined;
        if (enableValidationLayers) {
            createInfo.enabledLayerCount   = validationLayers.len;
            createInfo.ppEnabledLayerNames = validationLayers.ptr;

            populateDebugMessengerCreateInfo(&debugCreateInfo);
            createInfo.pNext = &debugCreateInfo;
        } else {
            createInfo.enabledLayerCount = 0;
            createInfo.pNext             = null;
        }

        if (vk.vkCreateInstance(&createInfo, null, &self.instance) != vk.VK_SUCCESS) {
            return error.FailedToCreateInstance;
        }
    }

    fn populateDebugMessengerCreateInfo(createInfo: *vk.VkDebugUtilsMessengerCreateInfoEXT) void {
        createInfo.* = .{
            .sType           = vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            .messageSeverity = vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            .messageType     = vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
            .pfnUserCallback = debugCallback,
            .pUserData       = null,
        };
    }

    fn setupDebugMessenger(self: *HelloTriangleApplication) !void {
        if (!enableValidationLayers) {
            return;
        }

        var createInfo: vk.VkDebugUtilsMessengerCreateInfoEXT = undefined;
        populateDebugMessengerCreateInfo(&createInfo);
        if (createDebugUtilMessengerEXT(self.instance, &createInfo, null, &self.debugMessenger) != vk.VK_SUCCESS) {
            return error.FailedToSetupDebugMessenger;
        }
    }

    fn createSurface(self: *HelloTriangleApplication) !void {
        if (glfwLib.glfwCreateWindowSurface(self.instance, self.window, null, &self.surface) != vk.VK_SUCCESS) {
            return error.FailedToCreateAWindowSurface;
        }
    }

    fn pickPhysicalDevice(self: *HelloTriangleApplication) !void {
        var deviceCount: u32 = 0;
        _ = vk.vkEnumeratePhysicalDevices(self.instance, &deviceCount, null);
        if (deviceCount == 0) {
            return error.FailedToFindGpuWithVulkanSupport;
        }

        const devices = try self.allocator.alloc(vk.VkPhysicalDevice, deviceCount);
        defer self.allocator.free(devices);
        _ = vk.vkEnumeratePhysicalDevices(self.instance, &deviceCount, devices.ptr);
        for (devices) |device| {
            if (try isDeviceSuitable(device, self.surface, self.allocator)) {
                self.physicalDevice = device;
                break;
            }
        }

        if (self.physicalDevice == @as(vk.VkPhysicalDevice, @ptrCast(vk.VK_NULL_HANDLE))) {
            return error.FailedToFindASuitableGpu;
        }
    }

    fn createLogicalDevice(self: *HelloTriangleApplication) !void {
        const familyIndices: QueueFamilyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);

        var queueCreateInfos    = std.ArrayList(vk.VkDeviceQueueCreateInfo).init(self.allocator.*);
        defer queueCreateInfos.deinit();
        var uniqueQueueFamilies = std.AutoHashMap(u32, void).init(self.allocator.*);
        defer uniqueQueueFamilies.deinit();
        try uniqueQueueFamilies.put(familyIndices.graphicsFamily.?, {});
        try uniqueQueueFamilies.put(familyIndices.presentFamily.?, {});
        try uniqueQueueFamilies.put(familyIndices.transferFamily.?, {});

        const queuePriority: f32 = 1.0;
        var it                   = uniqueQueueFamilies.iterator();
        while (it.next()) |entry| {
            const queueCreateInfo: vk.VkDeviceQueueCreateInfo = .{
                .sType            = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = entry.key_ptr.*,
                .queueCount       = 1,
                .pQueuePriorities = &queuePriority,
            };
            try queueCreateInfos.append(queueCreateInfo);
        }

        var deviceFeatures: vk.VkPhysicalDeviceFeatures = .{
            .samplerAnisotropy = vk.VK_TRUE,
        };

        const createInfo: vk.VkDeviceCreateInfo = .{
            .sType                   = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount    = @intCast(queueCreateInfos.items.len),
            .pQueueCreateInfos       = queueCreateInfos.items.ptr,
            .pEnabledFeatures        = &deviceFeatures,
            .enabledExtensionCount   = @intCast(deviceExtensions.len),
            .ppEnabledExtensionNames = deviceExtensions.ptr,
        };
        if (vk.vkCreateDevice(self.physicalDevice, &createInfo, null, &self.device) != vk.VK_SUCCESS) {
            return error.FailedToCreateLogicalDevice;
        }

        vk.vkGetDeviceQueue(self.device, familyIndices.graphicsFamily.?, 0, &self.graphicsQueue);
        vk.vkGetDeviceQueue(self.device, familyIndices.presentFamily.?, 0, &self.presentQueue);
        vk.vkGetDeviceQueue(self.device, familyIndices.transferFamily.?, 0, &self.transferQueue);
    }

    fn createSwapChain(self: *HelloTriangleApplication) !void {
        const swapChainSupport = try querySwapChainSupport(self.physicalDevice, self.surface, self.allocator);
        defer swapChainSupport.deinit();

        const surfaceFormat       = chooseSwapSurfaceFormat(&swapChainSupport.formats);
        self.swapChainImageFormat = surfaceFormat.format;

        const presentMode = chooseSwapPresentMode(&swapChainSupport.presentModes);

        const extent         = chooseSwapExtent(self, &swapChainSupport.capabilities);
        self.swapChainExtent = extent;

        var imageCount: u32 = swapChainSupport.capabilities.minImageCount + 1;
        if (swapChainSupport.capabilities.maxImageCount > 0 and imageCount > swapChainSupport.capabilities.maxImageCount) {
            imageCount = swapChainSupport.capabilities.maxImageCount;
        }

        var createInfo: vk.VkSwapchainCreateInfoKHR = .{};
        createInfo.sType            = vk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
        createInfo.surface          = self.surface;
        createInfo.minImageCount    = imageCount;
        createInfo.imageFormat      = surfaceFormat.format;
        createInfo.imageExtent      = extent;
        createInfo.imageArrayLayers = 1;
        createInfo.imageUsage       = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

        const familyIndices: QueueFamilyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);
        if (familyIndices.graphicsFamily == familyIndices.presentFamily) {
            createInfo.imageSharingMode = vk.VK_SHARING_MODE_EXCLUSIVE;
        } else {
            createInfo.imageSharingMode = vk.VK_SHARING_MODE_CONCURRENT;
            createInfo.queueFamilyIndexCount = 2;
            const queueFamilyIndices         = [_]u32{ familyIndices.graphicsFamily.?, familyIndices.presentFamily.?};
            createInfo.pQueueFamilyIndices   = &queueFamilyIndices;
        }

        createInfo.preTransform   = swapChainSupport.capabilities.currentTransform;
        createInfo.compositeAlpha = vk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
        createInfo.presentMode    = presentMode;
        createInfo.clipped        = vk.VK_TRUE;
        createInfo.oldSwapchain   = @ptrCast(vk.VK_NULL_HANDLE);

        if (vk.vkCreateSwapchainKHR(self.device, &createInfo, null, &self.swapChain) != vk.VK_SUCCESS) {
            return error.FailedToCreateSwapChain;
        }

        _ = vk.vkGetSwapchainImagesKHR(self.device, self.swapChain, &imageCount, null);
        self.swapChainImages = try self.allocator.alloc(vk.VkImage, imageCount);
        _ = vk.vkGetSwapchainImagesKHR(self.device, self.swapChain, &imageCount, self.swapChainImages.ptr);
    }

    fn createImageViews(self: *HelloTriangleApplication) !void {
        self.swapChainImageViews = try self.allocator.alloc(vk.VkImageView, self.swapChainImages.len);

        for (0..self.swapChainImages.len) |i| {
            self.swapChainImageViews[i] = try self.createImageView(self.swapChainImages[i], self.swapChainImageFormat, vk.VK_IMAGE_ASPECT_COLOR_BIT);
        }
    }

    fn createRenderPass(self: *HelloTriangleApplication) !void {
        const colorAttachment: vk.VkAttachmentDescription = .{
            .format         = self.swapChainImageFormat,
            .samples        = vk.VK_SAMPLE_COUNT_1_BIT,
            .loadOp         = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp        = vk.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp  = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout  = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout    = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };

        const depthAttachment: vk.VkAttachmentDescription = .{
            .format         = try self.findDepthFormat(),
            .samples        = vk.VK_SAMPLE_COUNT_1_BIT,
            .loadOp         = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
            // NOTE: Depth data will not be used after drawing so we don't have to store it. According to the tutorial,
            // storing it will allow the hardware to perform additional optimizations (2025-08-25)
            .storeOp        = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .stencilLoadOp  = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout  = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout    = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };

        const colorAttachmentRef: vk.VkAttachmentReference = .{
            .attachment = 0,
            .layout     = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        const depthAttachmentRef: vk.VkAttachmentReference = .{
            .attachment = 1,
            .layout     = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };

        const subpass: vk.VkSubpassDescription = .{
            .pipelineBindPoint       = vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount    = 1,
            .pColorAttachments       = &colorAttachmentRef,
            .pDepthStencilAttachment = &depthAttachmentRef,
        };

        const dependency: vk.VkSubpassDependency = .{
            .srcSubpass    = vk.VK_SUBPASS_EXTERNAL,
            .dstSubpass    = 0,
            .srcStageMask  = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vk.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
            .srcAccessMask = vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
            .dstStageMask  = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        };

        const attachments = [_]vk.VkAttachmentDescription{ colorAttachment, depthAttachment };
        const renderPassInfo: vk.VkRenderPassCreateInfo = .{
            .sType           = vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = attachments.len,
            .pAttachments    = &attachments,
            .subpassCount    = 1,
            .pSubpasses      = &subpass,
            .dependencyCount = 1,
            .pDependencies   = &dependency,
        };

        if (vk.vkCreateRenderPass(self.device, &renderPassInfo, null, &self.renderPass) != vk.VK_SUCCESS) {
            return error.FailedToCreateRenderPass;
        }
    }

    fn createDescriptorSetLayout(self: *HelloTriangleApplication) !void {
        const uboLayoutBinding: vk.VkDescriptorSetLayoutBinding = .{
            .binding            = 0,
            .descriptorType     = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount    = 1,
            .stageFlags         = vk.VK_SHADER_STAGE_VERTEX_BIT,
            .pImmutableSamplers = null, // Optional
        };
        const samplerLayoutBinding: vk.VkDescriptorSetLayoutBinding = .{
            .binding            = 1,
            .descriptorType     = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount    = 1,
            .stageFlags         = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .pImmutableSamplers = null, // Optional
        };

        const bindings = [_]vk.VkDescriptorSetLayoutBinding{ uboLayoutBinding, samplerLayoutBinding };

        const layoutInfo: vk.VkDescriptorSetLayoutCreateInfo = .{
            .sType        = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = bindings.len,
            .pBindings    = &bindings,
        };

        if (vk.vkCreateDescriptorSetLayout(self.device, &layoutInfo, null, &self.descriptorSetLayout) != vk.VK_SUCCESS) {
            return error.FailedToCreateDescriptorSetLayout;
        }
    }

    fn createGraphicsPipeline(self: *HelloTriangleApplication) !void {
        const vertShaderCode = try readFile("shaders/vert.spv", self.allocator);
        defer self.allocator.free(vertShaderCode);
        const fragShaderCode = try readFile("shaders/frag.spv", self.allocator);
        defer self.allocator.free(fragShaderCode);

        const vertShaderModule: vk.VkShaderModule = try self.createShaderModule(vertShaderCode);
        const fragShaderModule: vk.VkShaderModule = try self.createShaderModule(fragShaderCode);

        const vertShaderStageInfo: vk.VkPipelineShaderStageCreateInfo = .{
            .sType  = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage  = vk.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vertShaderModule,
            .pName  = "main",
        };
        const fragShaderStageInfo: vk.VkPipelineShaderStageCreateInfo = .{
            .sType  = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage  = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = fragShaderModule,
            .pName  = "main",
        };

        const shaderStages = [_]vk.VkPipelineShaderStageCreateInfo{ vertShaderStageInfo, fragShaderStageInfo };

        const bindingDescription    = Vertex.getBindingDescription();
        const attributeDescriptions = Vertex.getAttributeDescriptions();
        const vertexInputInfo: vk.VkPipelineVertexInputStateCreateInfo = .{
            .sType                           = vk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount   = 1,
            .pVertexBindingDescriptions      = &bindingDescription,
            .vertexAttributeDescriptionCount = @intCast(attributeDescriptions.len),
            .pVertexAttributeDescriptions    = attributeDescriptions.ptr,
        };

        const inputAssembly: vk.VkPipelineInputAssemblyStateCreateInfo = .{
            .sType                  = vk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology               = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = vk.VK_FALSE,
        };

        const viewportState: vk.VkPipelineViewportStateCreateInfo = .{
            .sType         = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .scissorCount  = 1,
        };

        const rasterizer: vk.VkPipelineRasterizationStateCreateInfo = .{
            .sType                   = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable        = vk.VK_FALSE,
            .rasterizerDiscardEnable = vk.VK_FALSE,
            .polygonMode             = vk.VK_POLYGON_MODE_FILL,
            .lineWidth               = 1.0,
            .cullMode                = vk.VK_CULL_MODE_BACK_BIT,
            .frontFace               = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
            .depthBiasEnable         = vk.VK_FALSE,
        };

        const multisampling: vk.VkPipelineMultisampleStateCreateInfo = .{
            .sType                = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .sampleShadingEnable  = vk.VK_FALSE,
            .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT,
        };

        const depthStencil: vk.VkPipelineDepthStencilStateCreateInfo = .{
            .sType                 = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .depthTestEnable       = vk.VK_TRUE,
            .depthWriteEnable      = vk.VK_TRUE,
            .depthCompareOp        = vk.VK_COMPARE_OP_LESS,
            .depthBoundsTestEnable = vk.VK_FALSE,
            .stencilTestEnable     = vk.VK_FALSE,
        };

        const colorBlendAttachment: vk.VkPipelineColorBlendAttachmentState = .{
            .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
            .blendEnable    = vk.VK_FALSE,
        };
        const colorBlending: vk.VkPipelineColorBlendStateCreateInfo = .{
            .sType           = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable   = vk.VK_FALSE,
            .attachmentCount = 1,
            .pAttachments    = &colorBlendAttachment,
        };

        const dynamicStates = &[_]vk.VkDynamicState{
            vk.VK_DYNAMIC_STATE_VIEWPORT,
            vk.VK_DYNAMIC_STATE_SCISSOR,
        };
        const dynamicState: vk.VkPipelineDynamicStateCreateInfo = .{
            .sType             = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynamicStates.len,
            .pDynamicStates    = dynamicStates.ptr,
        };

        const pipelineLayoutInfo: vk.VkPipelineLayoutCreateInfo = .{
            .sType          = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 1,
            .pSetLayouts    = &self.descriptorSetLayout,
        };
        if (vk.vkCreatePipelineLayout(self.device, &pipelineLayoutInfo, null, &self.pipelineLayout) != vk.VK_SUCCESS) {
            return error.FailedToCreatePipelineLayout;
        }

        const pipelineInfo: vk.VkGraphicsPipelineCreateInfo = .{
            .sType               = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount          = 2,
            .pStages             = &shaderStages,
            .pVertexInputState   = &vertexInputInfo,
            .pInputAssemblyState = &inputAssembly,
            .pViewportState      = &viewportState,
            .pRasterizationState = &rasterizer,
            .pMultisampleState   = &multisampling,
            .pDepthStencilState  = &depthStencil,
            .pColorBlendState    = &colorBlending,
            .pDynamicState       = &dynamicState,
            .layout              = self.pipelineLayout,
            .renderPass          = self.renderPass,
            .subpass             = 0,
            .basePipelineHandle  = @ptrCast(vk.VK_NULL_HANDLE), // Optional
            .basePipelineIndex   = -1, // Optional
        };

        if (vk.vkCreateGraphicsPipelines(self.device, @ptrCast(vk.VK_NULL_HANDLE), 1, &pipelineInfo, null, &self.graphicsPipeline) != vk.VK_SUCCESS) {
            return error.FailedToCreateGraphicsPipeline;
        }

        vk.vkDestroyShaderModule(self.device, vertShaderModule, null);
        vk.vkDestroyShaderModule(self.device, fragShaderModule, null);
    }

    fn createFramebuffers(self: *HelloTriangleApplication) !void {
        self.swapChainFramebuffers = try self.allocator.alloc(vk.VkFramebuffer, self.swapChainImageViews.len);

        for (0..self.swapChainImageViews.len) |i| {
            const attachments = [_]vk.VkImageView{self.swapChainImageViews[i], self.depthImageView};

            const frameBufferInfo: vk.VkFramebufferCreateInfo = .{
                .sType           = vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass      = self.renderPass,
                .attachmentCount = attachments.len,
                .pAttachments    = &attachments,
                .width           = self.swapChainExtent.width,
                .height          = self.swapChainExtent.height,
                .layers          = 1,
            };

            if (vk.vkCreateFramebuffer(self.device, &frameBufferInfo, null, &self.swapChainFramebuffers[i]) != vk.VK_SUCCESS) {
                return error.FailedToCreateFramebuffer;
            }
        }
    }

    fn createCommandPool(self: *HelloTriangleApplication) !void {
        const queueFamilyIndices: QueueFamilyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);

        const graphicsPoolInfo: vk.VkCommandPoolCreateInfo = .{
            .sType            = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags            = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queueFamilyIndices.graphicsFamily.?,
        };

        if (vk.vkCreateCommandPool(self.device, &graphicsPoolInfo, null, &self.graphicsCommandPool) != vk.VK_SUCCESS) {
            return error.FailedToCreateGraphicsCommandPool;
        }

        const transferPoolInfo: vk.VkCommandPoolCreateInfo = .{
            .sType            = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags            = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queueFamilyIndices.transferFamily.?,
        };

        if (vk.vkCreateCommandPool(self.device, &transferPoolInfo, null, &self.transferCommandPool) != vk.VK_SUCCESS) {
            return error.FailedToCreateTransferCommandPool;
        }
    }

    fn createDepthResources(self: *HelloTriangleApplication) !void {
        const depthFormat = try self.findDepthFormat();

        try self.createImage(
            self.swapChainExtent.width,
            self.swapChainExtent.height,
            depthFormat,
            vk.VK_IMAGE_TILING_OPTIMAL,
            vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &self.depthImage,
            &self.depthImageMemory,
        );
        self.depthImageView = try self.createImageView(self.depthImage, depthFormat, vk.VK_IMAGE_ASPECT_DEPTH_BIT);
    }

    fn findSupportedFormat(
        self:       *HelloTriangleApplication,
        candidates: []const vk.VkFormat,
        tiling:     vk.VkImageTiling,
        features:   vk.VkFormatFeatureFlags,
    ) !vk.VkFormat {
        for (candidates) |format| {
            var props: vk.VkFormatProperties = undefined;
            vk.vkGetPhysicalDeviceFormatProperties(self.physicalDevice, format, &props);

            if (tiling == vk.VK_IMAGE_TILING_LINEAR and (props.linearTilingFeatures & features) == features) {
                return format;
            } else if (tiling == vk.VK_IMAGE_TILING_OPTIMAL and (props.optimalTilingFeatures & features) == features) {
                return format;
            }
        }

        return error.FailedToFindSupportedFormat;
    }

    fn findDepthFormat(self: *HelloTriangleApplication) !vk.VkFormat {
        return try self.findSupportedFormat(
            &.{ vk.VK_FORMAT_D32_SFLOAT, vk.VK_FORMAT_D32_SFLOAT_S8_UINT, vk.VK_FORMAT_D24_UNORM_S8_UINT },
            vk.VK_IMAGE_TILING_OPTIMAL,
            vk.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT,
        );
    }

    fn hasStencilComponent(format: vk.VkFormat) void {
        return format == vk.VK_FORMAT_D32_SFLOAT_S8_UINT or format == vk.VK_FORMAT_D24_UNORM_S8_UINT;
    }

    fn createTextureImage(self: *HelloTriangleApplication) !void {
        var texWidth:    c_int          = undefined;
        var texHeight:   c_int          = undefined;
        var texChannels: c_int          = undefined;
        const pixels:    ?*c.stbi_uc    = c.stbi_load(TEXTURE_PATH, &texWidth, &texHeight, &texChannels, c.STBI_rgb_alpha);
        defer c.stbi_image_free(pixels);
        const imageSize: vk.VkDeviceSize = @intCast(texWidth * texHeight * 4);

        if (pixels == null) {
            return error.FailedToLoadTextureImage;
        }

        var stagingBuffer:       vk.VkBuffer       = undefined;
        var stagingBufferMemory: vk.VkDeviceMemory = undefined;
        try self.createBuffer(
            imageSize,
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &stagingBuffer,
            &stagingBufferMemory,
        );

        var data: [*]c.stbi_uc = undefined;
        _ = vk.vkMapMemory(self.device, stagingBufferMemory, 0, imageSize, 0, @ptrCast(&data));
        @memcpy(data, @as([*]u8, @ptrCast(pixels.?))[0..imageSize]);
        vk.vkUnmapMemory(self.device, stagingBufferMemory);

        try self.createImage(
            @intCast(texWidth),
            @intCast(texHeight),
            vk.VK_FORMAT_R8G8B8A8_SRGB,
            vk.VK_IMAGE_TILING_OPTIMAL,
            vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &self.textureImage,
            &self.textureImageMemory,
        );

        try self.transitionImageLayout(self.textureImage, vk.VK_FORMAT_R8G8B8A8_SRGB, vk.VK_IMAGE_LAYOUT_UNDEFINED, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        try self.copyBufferToImage(stagingBuffer, self.textureImage, @intCast(texWidth), @intCast(texHeight));
        try self.transitionImageLayout(self.textureImage, vk.VK_FORMAT_R8G8B8A8_SRGB, vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

        vk.vkDestroyBuffer(self.device, stagingBuffer, null);
        vk.vkFreeMemory(self.device, stagingBufferMemory, null);
    }

    fn createTextureImageView(self: *HelloTriangleApplication) !void {
        self.textureImageView = try self.createImageView(self.textureImage, vk.VK_FORMAT_R8G8B8A8_SRGB, vk.VK_IMAGE_ASPECT_COLOR_BIT);
    }

    fn createImageView(
        self:        *HelloTriangleApplication,
        image:       vk.VkImage,
        format:      vk.VkFormat,
        aspectFlags: vk.VkImageAspectFlags,
    ) !vk.VkImageView {
        const viewInfo: vk.VkImageViewCreateInfo = .{
            .sType            = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image            = image,
            .viewType         = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format           = format,
            .subresourceRange = .{
                .aspectMask     = aspectFlags,
                .baseMipLevel   = 0,
                .levelCount     = 1,
                .baseArrayLayer = 0,
                .layerCount     = 1
            },
        };

        var imageView: vk.VkImageView = undefined;
        if (vk.vkCreateImageView(self.device, &viewInfo, null, &imageView) != vk.VK_SUCCESS) {
            return error.FailedToCreateImageView;
        }

        return imageView;
    }

    fn createTextureSampler(self: *HelloTriangleApplication) !void {
        var properties: vk.VkPhysicalDeviceProperties = undefined;
        vk.vkGetPhysicalDeviceProperties(self.physicalDevice, &properties);

        const samplerInfo: vk.VkSamplerCreateInfo = .{
            .sType                   = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter               = vk.VK_FILTER_LINEAR,
            .minFilter               = vk.VK_FILTER_LINEAR,
            .addressModeU            = vk.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeV            = vk.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeW            = vk.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .anisotropyEnable        = vk.VK_TRUE,
            .maxAnisotropy           = properties.limits.maxSamplerAnisotropy,
            .borderColor             = vk.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
            // VK_FALSE means normalized coordinates which is used more commonly in real world applications
            // because it allows the usage of textures of varying resolutions (2025-08-23)
            .unnormalizedCoordinates = vk.VK_FALSE,
            .compareEnable           = vk.VK_FALSE,
            .compareOp               = vk.VK_COMPARE_OP_ALWAYS,
            .mipmapMode              = vk.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        };

        if (vk.vkCreateSampler(self.device, &samplerInfo, null, &self.textureSampler) != vk.VK_SUCCESS) {
            return error.FailedToCreateTextureSampler;
        }
    }

    fn loadModel(self: *HelloTriangleApplication) !void {
        try ModelLoader.loadModel(&self.vertices, &self.indices, self.allocator);
    }

    fn createVertexBuffer(self: *HelloTriangleApplication) !void {
        const bufferSize: vk.VkDeviceSize = @sizeOf(@TypeOf(self.vertices.items[0])) * self.vertices.items.len;

        var stagingBuffer:       vk.VkBuffer       = undefined;
        var stagingBufferMemory: vk.VkDeviceMemory = undefined;
        try self.createBuffer(
            bufferSize,
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &stagingBuffer,
            &stagingBufferMemory,
        );

        var data: [*]Vertex = undefined;
        _ = vk.vkMapMemory(self.device, stagingBufferMemory, 0, bufferSize, 0, @ptrCast(&data));
        @memcpy(data, self.vertices.items[0..self.vertices.items.len]);
        vk.vkUnmapMemory(self.device, stagingBufferMemory);

        try self.createBuffer(
            bufferSize,
            vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &self.vertexBuffer,
            &self.vertexBufferMemory,
        );

        self.copyBuffer(stagingBuffer, self.vertexBuffer, bufferSize);

        vk.vkDestroyBuffer(self.device, stagingBuffer, null);
        vk.vkFreeMemory(self.device, stagingBufferMemory, null);
    }

    fn createIndexBuffer(self: *HelloTriangleApplication) !void {
        const bufferSize: vk.VkDeviceSize = @sizeOf(@TypeOf(self.indices.items[0])) * self.indices.items.len;

        var stagingBuffer:       vk.VkBuffer       = undefined;
        var stagingBufferMemory: vk.VkDeviceMemory = undefined;
        try self.createBuffer(
            bufferSize,
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &stagingBuffer,
            &stagingBufferMemory,
        );

        var data: [*]u32 = undefined;
        _ = vk.vkMapMemory(self.device, stagingBufferMemory, 0, bufferSize, 0, @ptrCast(&data));
        @memcpy(data, self.indices.items[0..self.indices.items.len]);
        vk.vkUnmapMemory(self.device, stagingBufferMemory);

        try self.createBuffer(
            bufferSize,
            vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &self.indexBuffer,
            &self.indexBufferMemory,
        );

        self.copyBuffer(stagingBuffer, self.indexBuffer, bufferSize);

        vk.vkDestroyBuffer(self.device, stagingBuffer, null);
        vk.vkFreeMemory(self.device, stagingBufferMemory, null);
    }

    fn createUniformBuffers(self: *HelloTriangleApplication) !void {
        const bufferSize = @sizeOf(UniformBufferObject);

        for (0..self.uniformBuffers.len) |i| {
            try self.createBuffer(
                bufferSize,
                vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                &self.uniformBuffers[i],
                &self.uniformBuffersMemory[i],
            );
            _ = vk.vkMapMemory(self.device, self.uniformBuffersMemory[i], 0, bufferSize, 0, @ptrCast(@alignCast(&self.uniformBuffersMapped[i])));
        }
    }

    fn createDescriptorPool(self: *HelloTriangleApplication) !void  {
        const poolSizes = [_]vk.VkDescriptorPoolSize{
            .{
                .type            = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = MAX_FRAMES_IN_FLIGHT,
            },
            .{
                .type            = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = MAX_FRAMES_IN_FLIGHT,
            },
        };

        const poolInfo: vk.VkDescriptorPoolCreateInfo = .{
            .sType         = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .flags         = vk.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
            .poolSizeCount = poolSizes.len,
            .pPoolSizes    = &poolSizes,
            .maxSets       = MAX_FRAMES_IN_FLIGHT,
        };

        if (vk.vkCreateDescriptorPool(self.device, &poolInfo, null, &self.descriptorPool) != vk.VK_SUCCESS) {
            return error.FailedToCreateDescriptorPool;
        }
    }

    fn createDescriptorSets(self: *HelloTriangleApplication) !void {
        var layouts: [MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSetLayout = undefined;
        for (0..layouts.len) |i| {
            layouts[i] = self.descriptorSetLayout;
        }
        const allocInfo: vk.VkDescriptorSetAllocateInfo = .{
            .sType              = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool     = self.descriptorPool,
            .descriptorSetCount = layouts.len,
            .pSetLayouts        = &layouts,
        };

        if (vk.vkAllocateDescriptorSets(self.device, &allocInfo, &self.descriptorSets) != vk.VK_SUCCESS) {
            return error.FailedToAllocateDescriptorSets;
        }

        for (0..self.descriptorSets.len) |i| {
            const bufferInfo: vk.VkDescriptorBufferInfo = .{
                .buffer = self.uniformBuffers[i],
                .offset = 0,
                .range  = @sizeOf(UniformBufferObject),
            };
            const imageInfo: vk.VkDescriptorImageInfo = .{
                .sampler     = self.textureSampler,
                .imageView   = self.textureImageView,
                .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            };

            const descriptorWrites = [_]vk.VkWriteDescriptorSet{
                .{
                    .sType            = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .dstSet           = self.descriptorSets[i],
                    .dstBinding       = 0,
                    .dstArrayElement  = 0,
                    .descriptorType   = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .descriptorCount  = 1,
                    .pBufferInfo      = &bufferInfo,
                    .pImageInfo       = null, // Optional
                    .pTexelBufferView = null, // Optional
                },
                .{
                    .sType            = vk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .dstSet           = self.descriptorSets[i],
                    .dstBinding       = 1,
                    .dstArrayElement  = 0,
                    .descriptorType   = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                    .descriptorCount  = 1,
                    .pImageInfo       = &imageInfo,
                    .pTexelBufferView = null, // Optional
                },
            };

            vk.vkUpdateDescriptorSets(self.device, @intCast(descriptorWrites.len), &descriptorWrites, 0, null);
        }
    }

    fn createBuffer(
        self:         *HelloTriangleApplication,
        size:         vk.VkDeviceSize,
        usage:        vk.VkBufferUsageFlags,
        properties:   vk.VkMemoryPropertyFlags,
        buffer:       *vk.VkBuffer,
        bufferMemory: *vk.VkDeviceMemory,
    ) !void {
        const familyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);
        const bufferInfo: vk.VkBufferCreateInfo = .{
            .sType                 = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size                  = size,
            .usage                 = usage,
            .sharingMode           = vk.VK_SHARING_MODE_CONCURRENT,
            .queueFamilyIndexCount = 2,
            .pQueueFamilyIndices   = &[_]u32{familyIndices.graphicsFamily.?, familyIndices.transferFamily.?},
        };
        if (vk.vkCreateBuffer(self.device, &bufferInfo, null, buffer) != vk.VK_SUCCESS) {
            return error.FailedToCreateVertexBuffer;
        }

        var memRequirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetBufferMemoryRequirements(self.device, buffer.*, &memRequirements);

        const allocInfo: vk.VkMemoryAllocateInfo = .{
            .sType           = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize  = memRequirements.size,
            .memoryTypeIndex = try self.findMemoryType(memRequirements.memoryTypeBits, properties),
        };
        // NOTE: It's not good to call vkAllocateMemory for each individual buffer in production code
        // because simultaneous memory allocations are limited by the maxMemoryAllocationCount physical device limit. (2025-03-06)
        if (vk.vkAllocateMemory(self.device, &allocInfo, null, bufferMemory) != vk.VK_SUCCESS) {
            return error.FailedToAllocateVertexBufferMemory;
        }

        _ = vk.vkBindBufferMemory(self.device, buffer.*, bufferMemory.*, 0);
    }

    fn createImage(
        self:        *HelloTriangleApplication,
        width:       u32,
        height:      u32,
        format:      vk.VkFormat,
        tiling:      vk.VkImageTiling,
        usage:       vk.VkImageUsageFlags,
        properties:  vk.VkMemoryPropertyFlags,
        image:       *vk.VkImage,
        imageMemory: *vk.VkDeviceMemory,
    ) !void {
        const imageInfo: vk.VkImageCreateInfo = .{
            .sType         = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType     = vk.VK_IMAGE_TYPE_2D,
            .extent        = .{
                .width  = width,
                .height = height,
                .depth  = 1,
            },
            .mipLevels     = 1,
            .arrayLayers   = 1,
            .format        = format,
            .tiling        = tiling,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage         = usage,
            .sharingMode   = vk.VK_SHARING_MODE_EXCLUSIVE,
            .samples       = vk.VK_SAMPLE_COUNT_1_BIT,
            .flags         = 0,
        };

        if (vk.vkCreateImage(self.device, &imageInfo, null, image) != vk.VK_SUCCESS) {
            return error.FailedToCreateImage;
        }

        var memRequirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetImageMemoryRequirements(self.device, image.*, &memRequirements);

        const allocInfo: vk.VkMemoryAllocateInfo = .{
            .sType           = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize  = memRequirements.size,
            .memoryTypeIndex = try self.findMemoryType(memRequirements.memoryTypeBits, properties),
        };

        if (vk.vkAllocateMemory(self.device, &allocInfo, null, imageMemory) != vk.VK_SUCCESS) {
            return error.FailedToALlocateImageMemory;
        }

        _ = vk.vkBindImageMemory(self.device, image.*, imageMemory.*, 0);
    }

    fn copyBuffer(self: *HelloTriangleApplication, srcBuffer: vk.VkBuffer, dstBuffer: vk.VkBuffer, size: vk.VkDeviceSize) void {
        const commandBuffer: vk.VkCommandBuffer = try self.beginSingleTimeCommands(self.transferCommandPool);

        var copyRegion: vk.VkBufferCopy = .{
            .srcOffset = 0, // Optional
            .dstOffset = 0, // Optional
            .size      = size,
        };
        vk.vkCmdCopyBuffer(commandBuffer, srcBuffer, dstBuffer, 1, &copyRegion);

        try self.endSingleTimeCommands(self.transferCommandPool, self.transferQueue, commandBuffer);
    }

    fn copyBufferToImage(self: *HelloTriangleApplication, buffer: vk.VkBuffer, image: vk.VkImage, width: u32, height: u32) !void {
        const commandBuffer: vk.VkCommandBuffer = try self.beginSingleTimeCommands(self.transferCommandPool);

        const region: vk.VkBufferImageCopy = .{
            .bufferOffset      = 0,
            .bufferRowLength   = 0,
            .bufferImageHeight = 0,
            .imageSubresource  = .{
                .aspectMask     = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel       = 0,
                .baseArrayLayer = 0,
                .layerCount     = 1,
            },
            .imageOffset       = .{
                .x = 0,
                .y = 0,
                .z = 0,
            },
            .imageExtent       = .{
                .width  = width,
                .height = height,
                .depth  = 1,
            },
        };

        vk.vkCmdCopyBufferToImage(
            commandBuffer,
            buffer,
            image,
            vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &region,
        );

        try self.endSingleTimeCommands(self.transferCommandPool, self.transferQueue, commandBuffer);
    }

    fn findMemoryType(self: *HelloTriangleApplication, typeFilter: u32, properties: vk.VkMemoryPropertyFlags) !u32 {
        var memProperties: vk.VkPhysicalDeviceMemoryProperties = undefined;
        vk.vkGetPhysicalDeviceMemoryProperties(self.physicalDevice, &memProperties);
        for (0..memProperties.memoryTypeCount) |i| {
            const bit = @as(u32, 1) << @intCast(i);
            if (typeFilter & bit != 0 and (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
                return @intCast(i);
            }
        }
        return error.FailedToFindSuitableMemoryType;
    }

    fn updateUniformBuffer(self: *HelloTriangleApplication, currentImage: u32) void {
        const currentTime = std.time.timestamp();
        const time: f32   = @floatFromInt(currentTime - self.startTime);

        var ubo: UniformBufferObject align(32) = .{};
        cglm.glm_mat4_identity(&ubo.model);
        cglm.glm_mat4_identity(&ubo.view);
        cglm.glm_mat4_identity(&ubo.proj);

        cglm.glm_rotate(&ubo.model, time * cglm.glm_rad(90.0), @constCast(&cglm.vec3{0.0, 0.0, 1.0}));
        cglm.glm_lookat(@constCast(&cglm.vec3{2.0, 2.0, 2.0}), @constCast(&cglm.vec3{0.0, 0.0, 0.0}), @constCast(&cglm.vec3{0.0, 0.0, 1.0}), &ubo.view);
        const width:  f32 = @floatFromInt(self.swapChainExtent.width);
        const height: f32 = @floatFromInt(self.swapChainExtent.height);
        cglm.glm_perspective(cglm.glm_rad(45.0), width / height, 0.1, 10.0, &ubo.proj);
        ubo.proj[1][1] *= -1;

        self.uniformBuffersMapped[currentImage].* = ubo;
    }

    fn createCommandBuffers(self: *HelloTriangleApplication) !void {
        const allocInfoGraphics: vk.VkCommandBufferAllocateInfo = .{
            .sType              = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool        = self.graphicsCommandPool,
            .level              = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = @intCast(self.graphicsCommandBuffers.len),
        };

        if (vk.vkAllocateCommandBuffers(self.device, &allocInfoGraphics, &self.graphicsCommandBuffers) != vk.VK_SUCCESS) {
            return error.FailedToCreateGraphicsCommandBuffers;
        }

        const allocInfoTransfer: vk.VkCommandBufferAllocateInfo = .{
            .sType              = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool        = self.transferCommandPool,
            .level              = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = @intCast(self.transferCommandBuffers.len),
        };

        if (vk.vkAllocateCommandBuffers(self.device, &allocInfoTransfer, &self.transferCommandBuffers) != vk.VK_SUCCESS) {
            return error.FailedToCreateTransferCommandBuffers;
        }
    }

    fn createSyncObjects(self: *HelloTriangleApplication) !void {
        const semaphoreInfo: vk.VkSemaphoreCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        const fenceInfo: vk.VkFenceCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            if (vk.vkCreateSemaphore(self.device, &semaphoreInfo, null, &self.imageAvailableSemaphores[i]) != vk.VK_SUCCESS or
                vk.vkCreateSemaphore(self.device, &semaphoreInfo, null, &self.renderFinishedSemaphores[i]) != vk.VK_SUCCESS or
                vk.vkCreateFence(self.device, &fenceInfo, null, &self.inFlightFences[i]) != vk.VK_SUCCESS)
            {
                return error.FailedToCreateSemaphores;
            }
        }
    }

    fn recordCommandBuffer(self: *HelloTriangleApplication, commandBuffer: vk.VkCommandBuffer, imageIndex: u32) !void {
        const beginInfo: vk.VkCommandBufferBeginInfo = .{
            .sType            = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags            = 0,    // Optional
            .pInheritanceInfo = null, // Optional
        };

        if (vk.vkBeginCommandBuffer(commandBuffer, &beginInfo) != vk.VK_SUCCESS) {
            return error.FailedToBeginRecordingFramebuffer;
        }

        const clearValues = [_]vk.VkClearValue{
            .{.color = .{ .float32 = .{0.0, 0.0, 0.0, 1.0} }},
            .{.depthStencil = .{ .depth = 1.0, .stencil = 0}},
        };
        const renderPassInfo: vk.VkRenderPassBeginInfo = .{
            .sType           = vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass      = self.renderPass,
            .framebuffer     = self.swapChainFramebuffers[imageIndex],
            .renderArea      = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swapChainExtent,
            },
            .clearValueCount = clearValues.len,
            .pClearValues    = &clearValues,
        };


        vk.vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, vk.VK_SUBPASS_CONTENTS_INLINE);

        vk.vkCmdBindPipeline(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.graphicsPipeline);
        const viewPort: vk.VkViewport = .{
            .x        = 0.0,
            .y        = 0.0,
            .width    = @floatFromInt(self.swapChainExtent.width),
            .height   = @floatFromInt(self.swapChainExtent.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        vk.vkCmdSetViewport(commandBuffer, 0, 1, &viewPort);

        const scissor: vk.VkRect2D = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapChainExtent,
        };
        vk.vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

        const vertexBuffers = [_]vk.VkBuffer{self.vertexBuffer};
        const offsets       = [_]vk.VkDeviceSize{0};
        vk.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers, &offsets);

        vk.vkCmdBindIndexBuffer(commandBuffer, self.indexBuffer, 0, vk.VK_INDEX_TYPE_UINT32);

        vk.vkCmdBindDescriptorSets(commandBuffer, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelineLayout, 0, 1, &self.descriptorSets[self.currentFrame], 0, null);

        vk.vkCmdDrawIndexed(commandBuffer, @intCast(self.indices.items.len), 1, 0, 0, 0);

        vk.vkCmdEndRenderPass(commandBuffer);

        if (vk.vkEndCommandBuffer(commandBuffer) != vk.VK_SUCCESS) {
            return error.FailedToRecordCommandBuffer;
        }
    }

    fn beginSingleTimeCommands(self: *HelloTriangleApplication, commandPool: vk.VkCommandPool) !vk.VkCommandBuffer {
        const allocInfo: vk.VkCommandBufferAllocateInfo = .{
            .sType              = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .level              = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandPool        = commandPool,
            .commandBufferCount = 1,
        };
        var commandBuffer: vk.VkCommandBuffer = undefined;
        _ = vk.vkAllocateCommandBuffers(self.device, &allocInfo, &commandBuffer);

        const beginInfo: vk.VkCommandBufferBeginInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };
        _ = vk.vkBeginCommandBuffer(commandBuffer, &beginInfo);

        return commandBuffer;
    }

    fn endSingleTimeCommands(
        self:          *HelloTriangleApplication,
        commandPool:   vk.VkCommandPool,
        queue:         vk.VkQueue,
        commandBuffer: vk.VkCommandBuffer
    ) !void {
        _ = vk.vkEndCommandBuffer(commandBuffer);

        const submitInfo: vk.VkSubmitInfo = .{
            .sType              = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers    = &commandBuffer,
        };
        _ = vk.vkQueueSubmit(queue, 1, &submitInfo, @ptrCast(vk.VK_NULL_HANDLE));

        _ = vk.vkQueueWaitIdle(queue);

        vk.vkFreeCommandBuffers(self.device, commandPool, 1, &commandBuffer);
    }

    fn transitionImageLayout(
        self:      *HelloTriangleApplication,
        image:     vk.VkImage,
        format:    vk.VkFormat,
        oldLayout: vk.VkImageLayout,
        newLayout: vk.VkImageLayout,
    ) !void {
        _ = format;

        const commandBuffer: vk.VkCommandBuffer = try self.beginSingleTimeCommands(self.graphicsCommandPool);

        var barrier: vk.VkImageMemoryBarrier = .{
            .sType               = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout           = oldLayout,
            .newLayout           = newLayout,
            .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .image               = image,
            .subresourceRange    = .{
                .aspectMask     = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel   = 0,
                .levelCount     = 1,
                .baseArrayLayer = 0,
                .layerCount     = 1,
            },
            .srcAccessMask       = 0, // TODO
            .dstAccessMask       = 0, // TODO
        };

        var sourceStage:      vk.VkPipelineStageFlags = undefined;
        var destinationStage: vk.VkPipelineStageFlags = undefined;
        if (oldLayout == vk.VK_IMAGE_LAYOUT_UNDEFINED and newLayout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
            barrier.srcAccessMask = 0;
            barrier.dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;

            sourceStage      = vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
            destinationStage = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
        } else if (oldLayout == vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and newLayout == vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
            barrier.srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT;
            barrier.dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT;

            sourceStage      = vk.VK_PIPELINE_STAGE_TRANSFER_BIT;
            destinationStage = vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
        } else {
            return error.UnsupportedLayoutTransition;
        }

        vk.vkCmdPipelineBarrier(
            commandBuffer,
            sourceStage,
            destinationStage,
            0,
            0,
            null,
            0,
            null,
            1, 
            &barrier,
        );

        try self.endSingleTimeCommands(self.graphicsCommandPool, self.graphicsQueue, commandBuffer);
    }

    fn drawFrame(self: *HelloTriangleApplication) !void {
        _ = vk.vkWaitForFences(self.device, 1, &self.inFlightFences[self.currentFrame], vk.VK_TRUE, vk.UINT64_MAX);

        var imageIndex: u32 = undefined;

        switch (vk.vkAcquireNextImageKHR(self.device, self.swapChain, vk.UINT64_MAX, self.imageAvailableSemaphores[self.currentFrame], @ptrCast(vk.VK_NULL_HANDLE), &imageIndex)) {
            vk.VK_SUCCESS, vk.VK_SUBOPTIMAL_KHR => {},
            vk.VK_ERROR_OUT_OF_DATE_KHR => {
                try self.recreateSwapChain();
                return;
            },
            else => return error.FailedToAcquireSwapChainImage,

        }

        self.updateUniformBuffer(self.currentFrame);

        _ = vk.vkResetFences(self.device, 1, &self.inFlightFences[self.currentFrame]);

        _ = vk.vkResetCommandBuffer(self.graphicsCommandBuffers[self.currentFrame], 0);
        try self.recordCommandBuffer(self.graphicsCommandBuffers[self.currentFrame], imageIndex);

        const waitSemaphores   = [_]vk.VkSemaphore{self.imageAvailableSemaphores[self.currentFrame]};
        const waitStages       = [_]vk.VkPipelineStageFlags{vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
        const signalSemaphores = [_]vk.VkSemaphore{self.renderFinishedSemaphores[self.currentFrame]};
        const submitInfo:       vk.VkSubmitInfo = .{
            .sType                = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount   = 1,
            .pWaitSemaphores      = &waitSemaphores,
            .pWaitDstStageMask    = &waitStages,
            .commandBufferCount   = 1,
            .pCommandBuffers      = &self.graphicsCommandBuffers[self.currentFrame],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores    = &signalSemaphores,
        };

        // This follows the official Khronos Vulkan Tutorial logic, so this will cause the validation layer to
        // warn about using a semaphore that might still be in use (2025-05-29)
        if (vk.vkQueueSubmit(self.graphicsQueue, 1, &submitInfo, self.inFlightFences[self.currentFrame]) != vk.VK_SUCCESS) {
            return error.FailedToSubmitDrawCommandBuffer;
        }

        const swapChains                      = &[_]vk.VkSwapchainKHR{self.swapChain};
        const presentInfo: vk.VkPresentInfoKHR = .{
            .sType              = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores    = &signalSemaphores,
            .swapchainCount     = 1,
            .pSwapchains        = swapChains.ptr,
            .pImageIndices      = &imageIndex,
            .pResults           = null, // Optional
        };

        const result = vk.vkQueuePresentKHR(self.presentQueue, &presentInfo);
        if (result == vk.VK_ERROR_OUT_OF_DATE_KHR or result == vk.VK_SUBOPTIMAL_KHR or self.framebufferResized) {
            self.framebufferResized = false;
            try self.recreateSwapChain();
        } else if (result != vk.VK_SUCCESS) {
            return error.FailedToPresentSwapChainImage;
        }

        self.currentFrame = (self.currentFrame + 1) % MAX_FRAMES_IN_FLIGHT;
    }

    fn createShaderModule(self: *HelloTriangleApplication, code: []u8) !vk.VkShaderModule {
        const createInfo: vk.VkShaderModuleCreateInfo = .{
            .sType    = vk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = code.len,
            .pCode    = @ptrCast(@alignCast(code.ptr)),
        };

        var shaderModule: vk.VkShaderModule = undefined;
        if (vk.vkCreateShaderModule(self.device, &createInfo, null, &shaderModule) != vk.VK_SUCCESS) {
            return error.FailedToCreateShaderModule;
        }

        return shaderModule;
    }

    fn chooseSwapSurfaceFormat(availableFormats: *const std.ArrayList(vk.VkSurfaceFormatKHR)) vk.VkSurfaceFormatKHR {
        for (availableFormats.items) |availableFormat| {
            if (availableFormat.format == vk.VK_FORMAT_B8G8R8A8_SRGB and availableFormat.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                return availableFormat;
            }
        }
        return availableFormats.items[0];
    }

    fn chooseSwapPresentMode(availablePresentModes: *const std.ArrayList(vk.VkPresentModeKHR)) vk.VkPresentModeKHR {
        for (availablePresentModes.items) |availablePresentMode| {
            if (availablePresentMode == vk.VK_PRESENT_MODE_MAILBOX_KHR) {
                return availablePresentMode;
            }
        }
        return vk.VK_PRESENT_MODE_FIFO_KHR;
    }

    fn chooseSwapExtent(self: *HelloTriangleApplication, capabilities: *const vk.VkSurfaceCapabilitiesKHR) vk.VkExtent2D {
        if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
            return capabilities.currentExtent;
        }

        var width:  u32 = undefined;
        var height: u32 = undefined;
        glfw.glfwGetFramebufferSize(self.window, @ptrCast(&width), @ptrCast(&height));

        const actualExtent: vk.VkExtent2D = .{
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

    fn querySwapChainSupport(
        device:    vk.VkPhysicalDevice,
        surface:   vk.VkSurfaceKHR,
        allocator: *const std.mem.Allocator,
    ) !*SwapChainSupportDetails {
        var details: *SwapChainSupportDetails = try SwapChainSupportDetails.init(allocator);

        _ = vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities);

        var formatCount: u32 = 0;
        _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, null);
        if (formatCount != 0) {
            try details.formats.ensureTotalCapacity(formatCount);
            try details.formats.resize(formatCount);
            _ = vk.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, details.formats.items.ptr);
        }

        var presentModeCount: u32 = 0;
        _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, null);
        if (presentModeCount != 0) {
            try details.presentModes.ensureTotalCapacity(presentModeCount);
            try details.presentModes.resize(presentModeCount);
            _ = vk.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, details.presentModes.items.ptr);
        }

        return details;
    }

    fn isDeviceSuitable(
        device:    vk.VkPhysicalDevice,
        surface:   vk.VkSurfaceKHR,
        allocator: *const std.mem.Allocator,
    ) !bool {
        const familyIndices: QueueFamilyIndices = try findQueueFamilies(device, surface, allocator);

        const extensionsSupported: bool = try checkDeviceExtensionSupport(device, allocator);
        if (!extensionsSupported) {
            return false;
        }

        var swapChainSupport: *SwapChainSupportDetails = try querySwapChainSupport(device, surface, allocator);
        defer swapChainSupport.deinit();
        const swapChainAdequate: bool = swapChainSupport.formats.items.len > 0 and swapChainSupport.presentModes.items.len > 0;

        var supportedFeatures: vk.VkPhysicalDeviceFeatures = undefined;
        vk.vkGetPhysicalDeviceFeatures(device, &supportedFeatures);

        return familyIndices.isComplete()
            and swapChainAdequate
            and supportedFeatures.samplerAnisotropy == vk.VK_TRUE;
    }

    fn checkDeviceExtensionSupport(device: vk.VkPhysicalDevice, allocator: *const std.mem.Allocator) !bool {
        var extensionCount: u32 = 0;
        _ = vk.vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, null);

        const availableExtensions = try allocator.alloc(vk.VkExtensionProperties, extensionCount);
        defer allocator.free(availableExtensions);
        _ = vk.vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, availableExtensions.ptr);

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

    fn findQueueFamilies(device: vk.VkPhysicalDevice, surface: vk.VkSurfaceKHR, allocator: *const std.mem.Allocator) !QueueFamilyIndices {
        var familyIndices: QueueFamilyIndices = .{
            .graphicsFamily = null,
            .presentFamily  = null,
            .transferFamily = null,
        };

        var queueFamilyCount: u32 = 0;
        vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
        const queueFamilies       = try allocator.alloc(vk.VkQueueFamilyProperties, queueFamilyCount);
        defer allocator.free(queueFamilies);
        vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);
        for (queueFamilies, 0..) |queueFamily, i| {
            // NOTE: The same queue family used for both drawing and presentation
            // would yield improved performance compared to this loop implementation
            // (even though it can happen in this implementation that the same queue family
            // gets selected for both). (2025-04-19)
            // IMPORTANT: There is no fallback for when the transfer queue family is not found
            // because the tutorial task requires a strictly transfer-only queue family (2025-06-04)

            if ((queueFamily.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT) != 0) {
                familyIndices.graphicsFamily = @intCast(i);
            } else if ((queueFamily.queueFlags & vk.VK_QUEUE_TRANSFER_BIT) != 0) {
                familyIndices.transferFamily = @intCast(i);
            }

            var doesSupportPresent: vk.VkBool32 = 0;
            _ = vk.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface, &doesSupportPresent);
            if (doesSupportPresent != 0) {
                familyIndices.presentFamily = @intCast(i);
            }

            if (familyIndices.isComplete()) {
                break;
            }
        }

        return familyIndices;
    }

    fn getRequiredExtensions(allocator: *const std.mem.Allocator) !std.ArrayList([*c]const u8) {
        var glfwExtensionCount: u32              = 0;
        const glfwExtensions:   [*c][*c]const u8 = glfw.glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

        var extensions = std.ArrayList([*c]const u8).init(allocator.*);
        for (0..glfwExtensionCount) |i| {
            try extensions.append(glfwExtensions[i]);
        }
        if (enableValidationLayers) {
            try extensions.append(vk.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        }

        return extensions;
    }

    fn checkValidationLayerSupport(allocator: *const std.mem.Allocator) !bool {
        var layerCount: u32 = 0;
        _ = vk.vkEnumerateInstanceLayerProperties(&layerCount, null);

        const availableLayers = try allocator.alloc(vk.VkLayerProperties, layerCount);
        defer allocator.free(availableLayers);
        _ = vk.vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.ptr);

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
        messageSeverity: vk.VkDebugUtilsMessageSeverityFlagBitsEXT,
        messageType:     vk.VkDebugUtilsMessageTypeFlagsEXT,
        pCallbackData:   [*c]const vk.VkDebugUtilsMessengerCallbackDataEXT,
        pUserData:       ?*anyopaque,
    ) callconv(.C) vk.VkBool32 {
        _, _, _ = .{&messageSeverity, &messageType, &pUserData};
        std.debug.print("validation layer: {s}\n", .{pCallbackData.*.pMessage});

        return vk.VK_FALSE;
    }

    fn readFile(fileName: []const u8, allocator: *const std.mem.Allocator) ![]u8 {
        const file = try std.fs.cwd().openFile(fileName, .{});
        defer file.close();

        const stat   = try file.stat();
        const buffer = try file.readToEndAlloc(allocator.*, stat.size);

        return buffer;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app: HelloTriangleApplication = .{ .allocator = &allocator, .startTime = std.time.timestamp()};

    try app.run();
}
