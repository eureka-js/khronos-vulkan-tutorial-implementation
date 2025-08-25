const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "");
    @cInclude("GLFW/glfw3.h");

    @cInclude("cglm/cglm.h");
    @cInclude("stb_image.h");
});

const std     = @import("std");
const builtin = @import("builtin");

const WIDTH:                u32 = 800;
const HEIGHT:               u32 = 600;
const MAX_FRAMES_IN_FLIGHT: u32 = 2;

const validationLayers       = &[_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
const enableValidationLayers = builtin.mode == .Debug;

const deviceExtensions       = &[_][*c]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

fn createDebugUtilMessengerEXT(
    instance:        c.VkInstance,
    pCreateInfo:     *c.VkDebugUtilsMessengerCreateInfoEXT,
    pAllocator:      ?*const c.VkAllocationCallbacks,
    pDebugMessenger: *c.VkDebugUtilsMessengerEXT,
) c.VkResult {
    const func: c.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
    if (func) |f| {
        return f(instance, pCreateInfo, pAllocator, pDebugMessenger);
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

const QueueFamilyIndices = struct {
    graphicsFamily: ?u32,
    presentFamily:  ?u32,
    transferFamily: ?u32,

    fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphicsFamily != null and self.presentFamily != null and self.transferFamily != null;
    }
};

const SwapChainSupportDetails = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats:      std.ArrayList(c.VkSurfaceFormatKHR),
    presentModes: std.ArrayList(c.VkPresentModeKHR),
    allocator:    *const std.mem.Allocator,

    fn init(allocator: *const std.mem.Allocator) !*SwapChainSupportDetails {
        const details        = try allocator.create(SwapChainSupportDetails);
        details.capabilities = undefined;
        details.formats      = std.ArrayList(c.VkSurfaceFormatKHR).init(allocator.*);
        details.presentModes = std.ArrayList(c.VkPresentModeKHR).init(allocator.*);
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

const Vertex = struct {
    pos:      c.vec2,
    color:    c.vec3,
    texCoord: c.vec2,

    fn getBindingDescription() c.VkVertexInputBindingDescription {
        const bindingDescription: c.VkVertexInputBindingDescription = .{
            .binding   = 0,
            .stride    = @sizeOf(@This()),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        return bindingDescription;
    }

    fn getAttributeDescriptions() []const c.VkVertexInputAttributeDescription {
        const attributeDescriptions = &[_]c.VkVertexInputAttributeDescription{
            .{
                .binding  = 0,
                .location = 0,
                .format   = c.VK_FORMAT_R32G32_SFLOAT,
                .offset   = @offsetOf(@This(), "pos"),
            },
            .{
                .binding  = 0,
                .location = 1,
                .format   = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset   = @offsetOf(@This(), "color"),
            },
            .{
                .binding  = 0,
                .location = 2,
                .format   = c.VK_FORMAT_R32G32_SFLOAT,
                .offset   = @offsetOf(@This(), "texCoord"),
            },
        };

        return attributeDescriptions;
    }
};

const vertices = [_]Vertex{
    .{.pos = .{-0.5, -0.5}, .color = .{1.0, 0.0, 0.0}, .texCoord = .{1.0, 0.0}},
    .{.pos = .{ 0.5, -0.5}, .color = .{0.0, 1.0, 0.0}, .texCoord = .{0.0, 0.0}},
    .{.pos = .{ 0.5,  0.5}, .color = .{0.0, 0.0, 1.0}, .texCoord = .{0.0, 1.0}},
    .{.pos = .{-0.5,  0.5}, .color = .{1.0, 1.0, 1.0}, .texCoord = .{1.0, 1.0}},
};

const indices = [_]u16{
    0, 1, 2, 2, 3, 0
};

const UniformBufferObject  = struct {
    model: c.mat4 align(16) = undefined,
    view:  c.mat4 align(16) = undefined,
    proj:  c.mat4 align(16) = undefined,
};

const HelloTriangleApplication = struct {
    window:  ?*c.GLFWwindow = undefined,
    surface: c.VkSurfaceKHR = undefined,

    swapChain:            c.VkSwapchainKHR = undefined,
    swapChainImages:      []c.VkImage      = undefined,
    swapChainImageFormat: c.VkFormat       = undefined,
    swapChainExtent:      c.VkExtent2D     = undefined,
    swapChainImageViews:  []c.VkImageView  = undefined,

    instance:       c.VkInstance               = undefined,
    debugMessenger: c.VkDebugUtilsMessengerEXT = undefined,

    physicalDevice: c.VkPhysicalDevice = @ptrCast(c.VK_NULL_HANDLE),
    device:         c.VkDevice         = undefined,

    graphicsQueue:  c.VkQueue = undefined,
    presentQueue:   c.VkQueue = undefined,
    transferQueue:  c.VkQueue = undefined,

    renderPass:          c.VkRenderPass          = undefined,
    descriptorSetLayout: c.VkDescriptorSetLayout = undefined,
    pipelineLayout:      c.VkPipelineLayout      = undefined,
    graphicsPipeline:    c.VkPipeline            = undefined,

    swapChainFramebuffers: []c.VkFramebuffer = undefined,

    graphicsCommandPool:    c.VkCommandPool                         = undefined,
    transferCommandPool:    c.VkCommandPool                         = undefined,
    graphicsCommandBuffers: [MAX_FRAMES_IN_FLIGHT]c.VkCommandBuffer = undefined,
    transferCommandBuffers: [MAX_FRAMES_IN_FLIGHT]c.VkCommandBuffer = undefined,

    textureImage:       c.VkImage        = undefined,
    textureImageMemory: c.VkDeviceMemory = undefined,
    textureImageView:   c.VkImageView    = undefined,
    textureSampler:     c.VkSampler      = undefined,

    vertexBuffer:       c.VkBuffer       = undefined,
    indexBuffer:        c.VkBuffer       = undefined,
    vertexBufferMemory: c.VkDeviceMemory = undefined,
    indexBufferMemory:  c.VkDeviceMemory = undefined,

    uniformBuffers:       [MAX_FRAMES_IN_FLIGHT]c.VkBuffer           = undefined,
    uniformBuffersMemory: [MAX_FRAMES_IN_FLIGHT]c.VkDeviceMemory     = undefined,
    uniformBuffersMapped: [MAX_FRAMES_IN_FLIGHT]*UniformBufferObject = undefined,

    descriptorPool: c.VkDescriptorPool                      = undefined,
    descriptorSets: [MAX_FRAMES_IN_FLIGHT]c.VkDescriptorSet = undefined,

    imageAvailableSemaphores: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = undefined,
    renderFinishedSemaphores: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = undefined,
    inFlightFences:           [MAX_FRAMES_IN_FLIGHT]c.VkFence     = undefined,
    currentFrame:             u32                                 = 0,

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
        if (c.glfwInit() == c.GLFW_FALSE) {
            return error.FailedGlfwInitialization;
        }

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        //c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);

        self.window = c.glfwCreateWindow(WIDTH, HEIGHT, "Vulkan", null, null);
        c.glfwSetWindowUserPointer(self.window, self);
        _ = c.glfwSetFramebufferSizeCallback(self.window, framebufferResizeCallback);
    }

    fn framebufferResizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
        _, _ = .{width, height};
        const app: ?*HelloTriangleApplication = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)));
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
        try self.createFramebuffers();
        try self.createCommandPools();
        try self.createTextureImage();
        try self.createTextureImageView();
        try self.createTextureSampler();
        try self.createVertexBuffer();
        try self.createIndexBuffer();
        try self.createUniformBuffers();
        try self.createDescriptorPool();
        try self.createDescriptorSets();
        try self.createCommandBuffers();
        try self.createSyncObjects();
    }

    fn mainLoop(self: *HelloTriangleApplication) !void {
        while (c.glfwWindowShouldClose(self.window.?) == 0) {
            c.glfwPollEvents();
            try self.drawFrame();
        }

        _ = c.vkDeviceWaitIdle(self.device);
    }

    fn cleanup(self: *HelloTriangleApplication) !void {
        self.cleanupSwapChain();

        c.vkDestroySampler(self.device, self.textureSampler, null);
        c.vkDestroyImageView(self.device, self.textureImageView, null);

        c.vkDestroyImage(self.device, self.textureImage, null);
        c.vkFreeMemory(self.device, self.textureImageMemory, null);

        c.vkDestroyPipeline(self.device, self.graphicsPipeline, null);
        c.vkDestroyPipelineLayout(self.device, self.pipelineLayout, null);
        c.vkDestroyRenderPass(self.device, self.renderPass, null);

        for (0..self.uniformBuffers.len) |i| {
            c.vkDestroyBuffer(self.device, self.uniformBuffers[i], null);
            c.vkFreeMemory(self.device, self.uniformBuffersMemory[i], null);
        }

        c.vkDestroyDescriptorPool(self.device, self.descriptorPool, null);

        c.vkDestroyDescriptorSetLayout(self.device, self.descriptorSetLayout, null);

        c.vkDestroyBuffer(self.device, self.vertexBuffer, null);
        c.vkFreeMemory(self.device, self.vertexBufferMemory, null);

        c.vkDestroyBuffer(self.device, self.indexBuffer, null);
        c.vkFreeMemory(self.device, self.indexBufferMemory, null);

        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            c.vkDestroySemaphore(self.device, self.imageAvailableSemaphores[i], null);
            c.vkDestroySemaphore(self.device, self.renderFinishedSemaphores[i], null);
            c.vkDestroyFence(self.device, self.inFlightFences[i], null);
        }

        c.vkDestroyCommandPool(self.device, self.graphicsCommandPool, null);
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

    fn cleanupSwapChain(self: *HelloTriangleApplication) void {
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

    fn recreateSwapChain(self: *HelloTriangleApplication) !void {
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

    fn createInstance(self: *HelloTriangleApplication) !void {
        if (enableValidationLayers and !(try checkValidationLayerSupport(self.allocator))) {
            return error.ValidationLayersNotFound;
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
        var createInfo: c.VkInstanceCreateInfo = .{};
        createInfo.sType                   = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        createInfo.pApplicationInfo        = &appInfo;
        createInfo.enabledExtensionCount   = @intCast(extensions.items.len);
        createInfo.ppEnabledExtensionNames = extensions.items.ptr;
        var debugCreateInfo: c.VkDebugUtilsMessengerCreateInfoEXT = undefined;
        if (enableValidationLayers) {
            createInfo.enabledLayerCount   = validationLayers.len;
            createInfo.ppEnabledLayerNames = validationLayers.ptr;

            populateDebugMessengerCreateInfo(&debugCreateInfo);
            createInfo.pNext = &debugCreateInfo;
        } else {
            createInfo.enabledLayerCount = 0;
            createInfo.pNext             = null;
        }

        if (c.vkCreateInstance(&createInfo, null, &self.instance) != c.VK_SUCCESS) {
            return error.FailedToCreateInstance;
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

    fn setupDebugMessenger(self: *HelloTriangleApplication) !void {
        if (!enableValidationLayers) {
            return;
        }

        var createInfo: c.VkDebugUtilsMessengerCreateInfoEXT = undefined;
        populateDebugMessengerCreateInfo(&createInfo);
        if (createDebugUtilMessengerEXT(self.instance, &createInfo, null, &self.debugMessenger) != c.VK_SUCCESS) {
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

        if (self.physicalDevice == @as(c.VkPhysicalDevice, @ptrCast(c.VK_NULL_HANDLE))) {
            return error.FailedToFindASuitableGpu;
        }
    }

    fn createLogicalDevice(self: *HelloTriangleApplication) !void {
        const familyIndices: QueueFamilyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);

        var queueCreateInfos    = std.ArrayList(c.VkDeviceQueueCreateInfo).init(self.allocator.*);
        defer queueCreateInfos.deinit();
        var uniqueQueueFamilies = std.AutoHashMap(u32, void).init(self.allocator.*);
        defer uniqueQueueFamilies.deinit();
        try uniqueQueueFamilies.put(familyIndices.graphicsFamily.?, {});
        try uniqueQueueFamilies.put(familyIndices.presentFamily.?, {});
        try uniqueQueueFamilies.put(familyIndices.transferFamily.?, {});

        const queuePriority: f32 = 1.0;
        var it                   = uniqueQueueFamilies.iterator();
        while (it.next()) |entry| {
            const queueCreateInfo: c.VkDeviceQueueCreateInfo = .{
                .sType            = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = entry.key_ptr.*,
                .queueCount       = 1,
                .pQueuePriorities = &queuePriority,
            };
            try queueCreateInfos.append(queueCreateInfo);
        }

        var deviceFeatures: c.VkPhysicalDeviceFeatures = .{
            .samplerAnisotropy = c.VK_TRUE,
        };

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

        c.vkGetDeviceQueue(self.device, familyIndices.graphicsFamily.?, 0, &self.graphicsQueue);
        c.vkGetDeviceQueue(self.device, familyIndices.presentFamily.?, 0, &self.presentQueue);
        c.vkGetDeviceQueue(self.device, familyIndices.transferFamily.?, 0, &self.transferQueue);
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

        var createInfo: c.VkSwapchainCreateInfoKHR = .{};
        createInfo.sType            = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
        createInfo.surface          = self.surface;
        createInfo.minImageCount    = imageCount;
        createInfo.imageFormat      = surfaceFormat.format;
        createInfo.imageExtent      = extent;
        createInfo.imageArrayLayers = 1;
        createInfo.imageUsage       = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

        const familyIndices: QueueFamilyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);
        if (familyIndices.graphicsFamily == familyIndices.presentFamily) {
            createInfo.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        } else {
            createInfo.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
            createInfo.queueFamilyIndexCount = 2;
            const queueFamilyIndices         = [_]u32{ familyIndices.graphicsFamily.?, familyIndices.presentFamily.?};
            createInfo.pQueueFamilyIndices   = &queueFamilyIndices;
        }

        createInfo.preTransform   = swapChainSupport.capabilities.currentTransform;
        createInfo.compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
        createInfo.presentMode    = presentMode;
        createInfo.clipped        = c.VK_TRUE;
        createInfo.oldSwapchain   = @ptrCast(c.VK_NULL_HANDLE);

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
            self.swapChainImageViews[i] = try self.createImageView(self.swapChainImages[i], self.swapChainImageFormat);
        }
    }

    fn createRenderPass(self: *HelloTriangleApplication) !void {
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

    fn createDescriptorSetLayout(self: *HelloTriangleApplication) !void {
        const uboLayoutBinding: c.VkDescriptorSetLayoutBinding = .{
            .binding            = 0,
            .descriptorType     = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount    = 1,
            .stageFlags         = c.VK_SHADER_STAGE_VERTEX_BIT,
            .pImmutableSamplers = null, // Optional
        };
        const samplerLayoutBinding: c.VkDescriptorSetLayoutBinding = .{
            .binding            = 1,
            .descriptorType     = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount    = 1,
            .stageFlags         = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .pImmutableSamplers = null, // Optional
        };

        const bindings = [_]c.VkDescriptorSetLayoutBinding{ uboLayoutBinding, samplerLayoutBinding };

        const layoutInfo: c.VkDescriptorSetLayoutCreateInfo = .{
            .sType        = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = bindings.len,
            .pBindings    = &bindings,
        };

        if (c.vkCreateDescriptorSetLayout(self.device, &layoutInfo, null, &self.descriptorSetLayout) != c.VK_SUCCESS) {
            return error.FailedToCreateDescriptorSetLayout;
        }
    }

    fn createGraphicsPipeline(self: *HelloTriangleApplication) !void {
        const vertShaderCode = try readFile("shaders/vert.spv", self.allocator);
        defer self.allocator.free(vertShaderCode);
        const fragShaderCode = try readFile("shaders/frag.spv", self.allocator);
        defer self.allocator.free(fragShaderCode);

        const vertShaderModule: c.VkShaderModule = try self.createShaderModule(vertShaderCode);
        const fragShaderModule: c.VkShaderModule = try self.createShaderModule(fragShaderCode);

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

        const shaderStages = [_]c.VkPipelineShaderStageCreateInfo{ vertShaderStageInfo, fragShaderStageInfo };

        const bindingDescription    = Vertex.getBindingDescription();
        const attributeDescriptions = Vertex.getAttributeDescriptions();
        const vertexInputInfo: c.VkPipelineVertexInputStateCreateInfo = .{
            .sType                           = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount   = 1,
            .pVertexBindingDescriptions      = &bindingDescription,
            .vertexAttributeDescriptionCount = @intCast(attributeDescriptions.len),
            .pVertexAttributeDescriptions    = attributeDescriptions.ptr,
        };

        const inputAssembly: c.VkPipelineInputAssemblyStateCreateInfo = .{
            .sType                  = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology               = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
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
            .lineWidth               = 1.0,
            .cullMode                = c.VK_CULL_MODE_BACK_BIT,
            .frontFace               = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
            .depthBiasEnable         = c.VK_FALSE,
        };

        const multisampling: c.VkPipelineMultisampleStateCreateInfo = .{
            .sType                = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .sampleShadingEnable  = c.VK_FALSE,
            .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        };

        const colorBlendAttachment: c.VkPipelineColorBlendAttachmentState = .{
            .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
            .blendEnable    = c.VK_FALSE,
        };
        const colorBlending: c.VkPipelineColorBlendStateCreateInfo = .{
            .sType           = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable   = c.VK_FALSE,
            .attachmentCount = 1,
            .pAttachments    = &colorBlendAttachment,
        };

        const dynamicStates = &[_]c.VkDynamicState{
            c.VK_DYNAMIC_STATE_VIEWPORT,
            c.VK_DYNAMIC_STATE_SCISSOR,
        };
        const dynamicState: c.VkPipelineDynamicStateCreateInfo = .{
            .sType             = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynamicStates.len,
            .pDynamicStates    = dynamicStates.ptr,
        };

        const pipelineLayoutInfo: c.VkPipelineLayoutCreateInfo = .{
            .sType          = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 1,
            .pSetLayouts    = &self.descriptorSetLayout,
        };
        if (c.vkCreatePipelineLayout(self.device, &pipelineLayoutInfo, null, &self.pipelineLayout) != c.VK_SUCCESS) {
            return error.FailedToCreatePipelineLayout;
        }

        const pipelineInfo: c.VkGraphicsPipelineCreateInfo = .{
            .sType               = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount          = 2,
            .pStages             = &shaderStages,
            .pVertexInputState   = &vertexInputInfo,
            .pInputAssemblyState = &inputAssembly,
            .pViewportState      = &viewportState,
            .pRasterizationState = &rasterizer,
            .pMultisampleState   = &multisampling,
            .pDepthStencilState  = null, // Optional
            .pColorBlendState    = &colorBlending,
            .pDynamicState       = &dynamicState,
            .layout              = self.pipelineLayout,
            .renderPass          = self.renderPass,
            .subpass             = 0,
            .basePipelineHandle  = @ptrCast(c.VK_NULL_HANDLE), // Optional
            .basePipelineIndex   = -1, // Optional
        };

        if (c.vkCreateGraphicsPipelines(self.device, @ptrCast(c.VK_NULL_HANDLE), 1, &pipelineInfo, null, &self.graphicsPipeline) != c.VK_SUCCESS) {
            return error.FailedToCreateGraphicsPipeline;
        }

        c.vkDestroyShaderModule(self.device, vertShaderModule, null);
        c.vkDestroyShaderModule(self.device, fragShaderModule, null);
    }

    fn createFramebuffers(self: *HelloTriangleApplication) !void {
        self.swapChainFramebuffers = try self.allocator.alloc(c.VkFramebuffer, self.swapChainImageViews.len);

        for (0..self.swapChainImageViews.len) |i| {
            const attachments = [_]c.VkImageView{ self.swapChainImageViews[i] };
            const frameBufferInfo: c.VkFramebufferCreateInfo = .{
                .sType           = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass      = self.renderPass,
                .attachmentCount = 1,
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

    fn createCommandPools(self: *HelloTriangleApplication) !void {
        const queueFamilyIndices: QueueFamilyIndices = try findQueueFamilies(self.physicalDevice, self.surface, self.allocator);

        const graphicsPoolInfo: c.VkCommandPoolCreateInfo = .{
            .sType            = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags            = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queueFamilyIndices.graphicsFamily.?,
        };

        if (c.vkCreateCommandPool(self.device, &graphicsPoolInfo, null, &self.graphicsCommandPool) != c.VK_SUCCESS) {
            return error.FailedToCreateGraphicsCommandPool;
        }

        const transferPoolInfo: c.VkCommandPoolCreateInfo = .{
            .sType            = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags            = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queueFamilyIndices.transferFamily.?,
        };

        if (c.vkCreateCommandPool(self.device, &transferPoolInfo, null, &self.transferCommandPool) != c.VK_SUCCESS) {
            return error.FailedToCreateTransferCommandPool;
        }
    }

    fn createTextureImage(self: *HelloTriangleApplication) !void {
        var texWidth:    c_int          = undefined;
        var texHeight:   c_int          = undefined;
        var texChannels: c_int          = undefined;
        const pixels:    ?*c.stbi_uc    = c.stbi_load("textures/texture.jpg", &texWidth, &texHeight, &texChannels, c.STBI_rgb_alpha);
        defer c.stbi_image_free(pixels);
        const imageSize: c.VkDeviceSize = @intCast(texWidth * texHeight * 4);

        if (pixels == null) {
            return error.FailedToLoadTextureImage;
        }

        var stagingBuffer:       c.VkBuffer       = undefined;
        var stagingBufferMemory: c.VkDeviceMemory = undefined;
        try self.createBuffer(
            imageSize,
            c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &stagingBuffer,
            &stagingBufferMemory,
        );

        var data: [*]c.stbi_uc = undefined;
        _ = c.vkMapMemory(self.device, stagingBufferMemory, 0, imageSize, 0, @ptrCast(&data));
        @memcpy(data, @as([*]u8, @ptrCast(pixels.?))[0..imageSize]);
        c.vkUnmapMemory(self.device, stagingBufferMemory);

        try self.createImage(
            @intCast(texWidth),
            @intCast(texHeight),
            c.VK_FORMAT_R8G8B8A8_SRGB,
            c.VK_IMAGE_TILING_OPTIMAL,
            c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT,
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &self.textureImage,
            &self.textureImageMemory,
        );

        try self.transitionImageLayout(self.textureImage, c.VK_FORMAT_R8G8B8A8_SRGB, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
        try self.copyBufferToImage(stagingBuffer, self.textureImage, @intCast(texWidth), @intCast(texHeight));
        try self.transitionImageLayout(self.textureImage, c.VK_FORMAT_R8G8B8A8_SRGB, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

        c.vkDestroyBuffer(self.device, stagingBuffer, null);
        c.vkFreeMemory(self.device, stagingBufferMemory, null);
    }

    fn createTextureImageView(self: *HelloTriangleApplication) !void {
        self.textureImageView = try self.createImageView(self.textureImage, c.VK_FORMAT_R8G8B8A8_SRGB);
    }

    fn createImageView(
        self:   *HelloTriangleApplication,
        image:  c.VkImage,
        format: c.VkFormat,
    ) !c.VkImageView {
        const viewInfo: c.VkImageViewCreateInfo = .{
            .sType            = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image            = image,
            .viewType         = c.VK_IMAGE_VIEW_TYPE_2D,
            .format           = format,
            .subresourceRange = .{
                .aspectMask     = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel   = 0,
                .levelCount     = 1,
                .baseArrayLayer = 0,
                .layerCount     = 1
            },
        };

        var imageView: c.VkImageView = undefined;
        if (c.vkCreateImageView(self.device, &viewInfo, null, &imageView) != c.VK_SUCCESS) {
            return error.FailedToCreateImageView;
        }

        return imageView;
    }

    fn createTextureSampler(self: *HelloTriangleApplication) !void {
        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(self.physicalDevice, &properties);

        const samplerInfo: c.VkSamplerCreateInfo = .{
            .sType                   = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter               = c.VK_FILTER_LINEAR,
            .minFilter               = c.VK_FILTER_LINEAR,
            .addressModeU            = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeV            = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .addressModeW            = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
            .anisotropyEnable        = c.VK_TRUE,
            .maxAnisotropy           = properties.limits.maxSamplerAnisotropy,
            .borderColor             = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
            // VK_FALSE means normalized coordinates which is used more commonly in real world applications
            // because it allows the usage of textures of varying resolutions (2025-08-23)
            .unnormalizedCoordinates = c.VK_FALSE,
            .compareEnable           = c.VK_FALSE,
            .compareOp               = c.VK_COMPARE_OP_ALWAYS,
            .mipmapMode              = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        };

        if (c.vkCreateSampler(self.device, &samplerInfo, null, &self.textureSampler) != c.VK_SUCCESS) {
            return error.FailedToCreateTextureSampler;
        }
    }

    fn createVertexBuffer(self: *HelloTriangleApplication) !void {
        const bufferSize: c.VkDeviceSize = @sizeOf(@TypeOf(vertices[0])) * vertices.len;

        var stagingBuffer:       c.VkBuffer       = undefined;
        var stagingBufferMemory: c.VkDeviceMemory = undefined;
        try self.createBuffer(
            bufferSize,
            c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &stagingBuffer,
            &stagingBufferMemory,
        );

        var data: [*]Vertex = undefined;
        _ = c.vkMapMemory(self.device, stagingBufferMemory, 0, bufferSize, 0, @ptrCast(&data));
        @memcpy(data, &vertices);
        c.vkUnmapMemory(self.device, stagingBufferMemory);

        try self.createBuffer(
            bufferSize,
            c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &self.vertexBuffer,
            &self.vertexBufferMemory,
        );

        self.copyBuffer(stagingBuffer, self.vertexBuffer, bufferSize);

        c.vkDestroyBuffer(self.device, stagingBuffer, null);
        c.vkFreeMemory(self.device, stagingBufferMemory, null);
    }

    fn createIndexBuffer(self: *HelloTriangleApplication) !void {
        const bufferSize: c.VkDeviceSize = @sizeOf(@TypeOf(indices[0])) * indices.len;

        var stagingBuffer:       c.VkBuffer       = undefined;
        var stagingBufferMemory: c.VkDeviceMemory = undefined;
        try self.createBuffer(
            bufferSize,
            c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &stagingBuffer,
            &stagingBufferMemory,
        );

        var data: [*]u16 = undefined;
        _ = c.vkMapMemory(self.device, stagingBufferMemory, 0, bufferSize, 0, @ptrCast(&data));
        @memcpy(data, &indices);
        c.vkUnmapMemory(self.device, stagingBufferMemory);

        try self.createBuffer(
            bufferSize,
            c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &self.indexBuffer,
            &self.indexBufferMemory,
        );

        self.copyBuffer(stagingBuffer, self.indexBuffer, bufferSize);

        c.vkDestroyBuffer(self.device, stagingBuffer, null);
        c.vkFreeMemory(self.device, stagingBufferMemory, null);
    }

    fn createUniformBuffers(self: *HelloTriangleApplication) !void {
        const bufferSize = @sizeOf(UniformBufferObject);

        for (0..self.uniformBuffers.len) |i| {
            try self.createBuffer(
                bufferSize,
                c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                &self.uniformBuffers[i],
                &self.uniformBuffersMemory[i],
            );
            _ = c.vkMapMemory(self.device, self.uniformBuffersMemory[i], 0, bufferSize, 0, @ptrCast(@alignCast(&self.uniformBuffersMapped[i])));
        }
    }

    fn createDescriptorPool(self: *HelloTriangleApplication) !void  {
        const poolSizes = [_]c.VkDescriptorPoolSize{
            .{
                .type            = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = MAX_FRAMES_IN_FLIGHT,
            },
            .{
                .type            = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .descriptorCount = MAX_FRAMES_IN_FLIGHT,
            },
        };

        const poolInfo: c.VkDescriptorPoolCreateInfo = .{
            .sType         = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .flags         = c.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
            .poolSizeCount = poolSizes.len,
            .pPoolSizes    = &poolSizes,
            .maxSets       = MAX_FRAMES_IN_FLIGHT,
        };

        if (c.vkCreateDescriptorPool(self.device, &poolInfo, null, &self.descriptorPool) != c.VK_SUCCESS) {
            return error.FailedToCreateDescriptorPool;
        }
    }

    fn createDescriptorSets(self: *HelloTriangleApplication) !void {
        var layouts: [MAX_FRAMES_IN_FLIGHT]c.VkDescriptorSetLayout = undefined;
        for (0..layouts.len) |i| {
            layouts[i] = self.descriptorSetLayout;
        }
        const allocInfo: c.VkDescriptorSetAllocateInfo = .{
            .sType              = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool     = self.descriptorPool,
            .descriptorSetCount = layouts.len,
            .pSetLayouts        = &layouts,
        };

        if (c.vkAllocateDescriptorSets(self.device, &allocInfo, &self.descriptorSets) != c.VK_SUCCESS) {
            return error.FailedToAllocateDescriptorSets;
        }

        for (0..self.descriptorSets.len) |i| {
            const bufferInfo: c.VkDescriptorBufferInfo = .{
                .buffer = self.uniformBuffers[i],
                .offset = 0,
                .range  = @sizeOf(UniformBufferObject),
            };
            const imageInfo: c.VkDescriptorImageInfo = .{
                .sampler     = self.textureSampler,
                .imageView   = self.textureImageView,
                .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            };

            const descriptorWrites = [_]c.VkWriteDescriptorSet{
                .{
                    .sType            = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .dstSet           = self.descriptorSets[i],
                    .dstBinding       = 0,
                    .dstArrayElement  = 0,
                    .descriptorType   = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                    .descriptorCount  = 1,
                    .pBufferInfo      = &bufferInfo,
                    .pImageInfo       = null, // Optional
                    .pTexelBufferView = null, // Optional
                },
                .{
                    .sType            = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                    .dstSet           = self.descriptorSets[i],
                    .dstBinding       = 1,
                    .dstArrayElement  = 0,
                    .descriptorType   = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                    .descriptorCount  = 1,
                    .pImageInfo       = &imageInfo,
                    .pTexelBufferView = null, // Optional
                },
            };

            c.vkUpdateDescriptorSets(self.device, @intCast(descriptorWrites.len), &descriptorWrites, 0, null);
        }
    }

    fn createBuffer(
        self:         *HelloTriangleApplication,
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
            .pQueueFamilyIndices   = &[_]u32{familyIndices.graphicsFamily.?, familyIndices.transferFamily.?},
        };
        if (c.vkCreateBuffer(self.device, &bufferInfo, null, buffer) != c.VK_SUCCESS) {
            return error.FailedToCreateVertexBuffer;
        }

        var memRequirements: c.VkMemoryRequirements = undefined;
        c.vkGetBufferMemoryRequirements(self.device, buffer.*, &memRequirements);

        const allocInfo: c.VkMemoryAllocateInfo = .{
            .sType           = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize  = memRequirements.size,
            .memoryTypeIndex = try self.findMemoryType(memRequirements.memoryTypeBits, properties),
        };
        // NOTE: It's not good to call vkAllocateMemory for each individual buffer in production code
        // because simultaneous memory allocations are limited by the maxMemoryAllocationCount physical device limit. (2025-03-06)
        if (c.vkAllocateMemory(self.device, &allocInfo, null, bufferMemory) != c.VK_SUCCESS) {
            return error.FailedToAllocateVertexBufferMemory;
        }

        _ = c.vkBindBufferMemory(self.device, buffer.*, bufferMemory.*, 0);
    }

    fn createImage(
        self:        *HelloTriangleApplication,
        width:       u32,
        height:      u32,
        format:      c.VkFormat,
        tiling:      c.VkImageTiling,
        usage:       c.VkImageUsageFlags,
        properties:  c.VkMemoryPropertyFlags,
        image:       *c.VkImage,
        imageMemory: *c.VkDeviceMemory,
    ) !void {
        const imageInfo: c.VkImageCreateInfo = .{
            .sType         = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType     = c.VK_IMAGE_TYPE_2D,
            .extent        = .{
                .width  = width,
                .height = height,
                .depth  = 1,
            },
            .mipLevels     = 1,
            .arrayLayers   = 1,
            .format        = format,
            .tiling        = tiling,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage         = usage,
            .sharingMode   = c.VK_SHARING_MODE_EXCLUSIVE,
            .samples       = c.VK_SAMPLE_COUNT_1_BIT,
            .flags         = 0,
        };

        if (c.vkCreateImage(self.device, &imageInfo, null, image) != c.VK_SUCCESS) {
            return error.FailedToCreateImage;
        }

        var memRequirements: c.VkMemoryRequirements = undefined;
        c.vkGetImageMemoryRequirements(self.device, image.*, &memRequirements);

        const allocInfo: c.VkMemoryAllocateInfo = .{
            .sType           = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize  = memRequirements.size,
            .memoryTypeIndex = try self.findMemoryType(memRequirements.memoryTypeBits, properties),
        };

        if (c.vkAllocateMemory(self.device, &allocInfo, null, imageMemory) != c.VK_SUCCESS) {
            return error.FailedToALlocateImageMemory;
        }

        _ = c.vkBindImageMemory(self.device, image.*, imageMemory.*, 0);
    }

    fn copyBuffer(self: *HelloTriangleApplication, srcBuffer: c.VkBuffer, dstBuffer: c.VkBuffer, size: c.VkDeviceSize) void {
        const commandBuffer: c.VkCommandBuffer = try self.beginSingleTimeCommands(self.transferCommandPool);

        var copyRegion: c.VkBufferCopy = .{
            .srcOffset = 0, // Optional
            .dstOffset = 0, // Optional
            .size      = size,
        };
        c.vkCmdCopyBuffer(commandBuffer, srcBuffer, dstBuffer, 1, &copyRegion);

        try self.endSingleTimeCommands(self.transferCommandPool, self.transferQueue, commandBuffer);
    }

    fn copyBufferToImage(self: *HelloTriangleApplication, buffer: c.VkBuffer, image: c.VkImage, width: u32, height: u32) !void {
        const commandBuffer: c.VkCommandBuffer = try self.beginSingleTimeCommands(self.transferCommandPool);

        const region: c.VkBufferImageCopy = .{
            .bufferOffset      = 0,
            .bufferRowLength   = 0,
            .bufferImageHeight = 0,
            .imageSubresource  = .{
                .aspectMask     = c.VK_IMAGE_ASPECT_COLOR_BIT,
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

        c.vkCmdCopyBufferToImage(
            commandBuffer,
            buffer,
            image,
            c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &region,
        );

        try self.endSingleTimeCommands(self.transferCommandPool, self.transferQueue, commandBuffer);
    }

    fn findMemoryType(self: *HelloTriangleApplication, typeFilter: u32, properties: c.VkMemoryPropertyFlags) !u32 {
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

    fn updateUniformBuffer(self: *HelloTriangleApplication, currentImage: u32) void {
        const currentTime = std.time.timestamp();
        const time: f32   = @floatFromInt(currentTime - self.startTime);

        var ubo: UniformBufferObject align(32) = .{};
        c.glm_mat4_identity(&ubo.model);
        c.glm_mat4_identity(&ubo.view);
        c.glm_mat4_identity(&ubo.proj);

        c.glm_rotate(&ubo.model, time * c.glm_rad(90.0), @constCast(&c.vec3{0.0, 0.0, 1.0}));
        c.glm_lookat(@constCast(&c.vec3{2.0, 2.0, 2.0}), @constCast(&c.vec3{0.0, 0.0, 0.0}), @constCast(&c.vec3{0.0, 0.0, 1.0}), &ubo.view);
        const width:  f32 = @floatFromInt(self.swapChainExtent.width);
        const height: f32 = @floatFromInt(self.swapChainExtent.height);
        c.glm_perspective(c.glm_rad(45.0), width / height, 0.1, 10.0, &ubo.proj);
        ubo.proj[1][1] *= -1;

        self.uniformBuffersMapped[currentImage].* = ubo;
    }

    fn createCommandBuffers(self: *HelloTriangleApplication) !void {
        const allocInfoGraphics: c.VkCommandBufferAllocateInfo = .{
            .sType              = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool        = self.graphicsCommandPool,
            .level              = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = @intCast(self.graphicsCommandBuffers.len),
        };

        if (c.vkAllocateCommandBuffers(self.device, &allocInfoGraphics, &self.graphicsCommandBuffers) != c.VK_SUCCESS) {
            return error.FailedToCreateGraphicsCommandBuffers;
        }

        const allocInfoTransfer: c.VkCommandBufferAllocateInfo = .{
            .sType              = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool        = self.transferCommandPool,
            .level              = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = @intCast(self.transferCommandBuffers.len),
        };

        if (c.vkAllocateCommandBuffers(self.device, &allocInfoTransfer, &self.transferCommandBuffers) != c.VK_SUCCESS) {
            return error.FailedToCreateTransferCommandBuffers;
        }
    }

    fn createSyncObjects(self: *HelloTriangleApplication) !void {
        const semaphoreInfo: c.VkSemaphoreCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        const fenceInfo: c.VkFenceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            if (c.vkCreateSemaphore(self.device, &semaphoreInfo, null, &self.imageAvailableSemaphores[i]) != c.VK_SUCCESS or
                c.vkCreateSemaphore(self.device, &semaphoreInfo, null, &self.renderFinishedSemaphores[i]) != c.VK_SUCCESS or
                c.vkCreateFence(self.device, &fenceInfo, null, &self.inFlightFences[i]) != c.VK_SUCCESS)
            {
                return error.FailedToCreateSemaphores;
            }
        }
    }

    fn recordCommandBuffer(self: *HelloTriangleApplication, commandBuffer: c.VkCommandBuffer, imageIndex: u32) !void {
        const beginInfo: c.VkCommandBufferBeginInfo = .{
            .sType            = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags            = 0,    // Optional
            .pInheritanceInfo = null, // Optional
        };

        if (c.vkBeginCommandBuffer(commandBuffer, &beginInfo) != c.VK_SUCCESS) {
            return error.FailedToBeginRecordingFramebuffer;
        }

        const clearColor:     c.VkClearValue          = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 1.0 } } };
        const renderPassInfo: c.VkRenderPassBeginInfo = .{
            .sType           = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass      = self.renderPass,
            .framebuffer     = self.swapChainFramebuffers[imageIndex],
            .renderArea      = .{
                .offset = .{ .x = 0, .y = 0 },
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
            .maxDepth = 1.0,
        };
        c.vkCmdSetViewport(commandBuffer, 0, 1, &viewPort);

        const scissor: c.VkRect2D = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swapChainExtent,
        };
        c.vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

        const vertexBuffers = [_]c.VkBuffer{self.vertexBuffer};
        const offsets       = [_]c.VkDeviceSize{0};
        c.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers, &offsets);

        c.vkCmdBindIndexBuffer(commandBuffer, self.indexBuffer, 0, c.VK_INDEX_TYPE_UINT16);

        c.vkCmdBindDescriptorSets(commandBuffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelineLayout, 0, 1, &self.descriptorSets[self.currentFrame], 0, null);

        c.vkCmdDrawIndexed(commandBuffer, indices.len, 1, 0, 0, 0);

        c.vkCmdEndRenderPass(commandBuffer);

        if (c.vkEndCommandBuffer(commandBuffer) != c.VK_SUCCESS) {
            return error.FailedToRecordCommandBuffer;
        }
    }

    fn beginSingleTimeCommands(self: *HelloTriangleApplication, commandPool: c.VkCommandPool) !c.VkCommandBuffer {
        const allocInfo: c.VkCommandBufferAllocateInfo = .{
            .sType              = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .level              = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandPool        = commandPool,
            .commandBufferCount = 1,
        };
        var commandBuffer: c.VkCommandBuffer = undefined;
        _ = c.vkAllocateCommandBuffers(self.device, &allocInfo, &commandBuffer);

        const beginInfo: c.VkCommandBufferBeginInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };
        _ = c.vkBeginCommandBuffer(commandBuffer, &beginInfo);

        return commandBuffer;
    }

    fn endSingleTimeCommands(
        self:          *HelloTriangleApplication,
        commandPool:   c.VkCommandPool,
        queue:         c.VkQueue,
        commandBuffer: c.VkCommandBuffer
    ) !void {
        _ = c.vkEndCommandBuffer(commandBuffer);

        const submitInfo: c.VkSubmitInfo = .{
            .sType              = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers    = &commandBuffer,
        };
        _ = c.vkQueueSubmit(queue, 1, &submitInfo, @ptrCast(c.VK_NULL_HANDLE));

        _ = c.vkQueueWaitIdle(queue);

        c.vkFreeCommandBuffers(self.device, commandPool, 1, &commandBuffer);
    }

    fn transitionImageLayout(
        self:      *HelloTriangleApplication,
        image:     c.VkImage,
        format:    c.VkFormat,
        oldLayout: c.VkImageLayout,
        newLayout: c.VkImageLayout,
    ) !void {
        _ = format;

        const commandBuffer: c.VkCommandBuffer = try self.beginSingleTimeCommands(self.graphicsCommandPool);

        var barrier: c.VkImageMemoryBarrier = .{
            .sType               = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout           = oldLayout,
            .newLayout           = newLayout,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .image               = image,
            .subresourceRange    = .{
                .aspectMask     = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel   = 0,
                .levelCount     = 1,
                .baseArrayLayer = 0,
                .layerCount     = 1,
            },
            .srcAccessMask       = 0, // TODO
            .dstAccessMask       = 0, // TODO
        };

        var sourceStage:      c.VkPipelineStageFlags = undefined;
        var destinationStage: c.VkPipelineStageFlags = undefined;
        if (oldLayout == c.VK_IMAGE_LAYOUT_UNDEFINED and newLayout == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
            barrier.srcAccessMask = 0;
            barrier.dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;

            sourceStage      = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
            destinationStage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
        } else if (oldLayout == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and newLayout == c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
            barrier.srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
            barrier.dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT;

            sourceStage      = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
            destinationStage = c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
        } else {
            return error.UnsupportedLayoutTransition;
        }

        c.vkCmdPipelineBarrier(
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
        _ = c.vkWaitForFences(self.device, 1, &self.inFlightFences[self.currentFrame], c.VK_TRUE, c.UINT64_MAX);

        var imageIndex: u32 = undefined;

        switch (c.vkAcquireNextImageKHR(self.device, self.swapChain, c.UINT64_MAX, self.imageAvailableSemaphores[self.currentFrame], @ptrCast(c.VK_NULL_HANDLE), &imageIndex)) {
            c.VK_SUCCESS, c.VK_SUBOPTIMAL_KHR => {},
            c.VK_ERROR_OUT_OF_DATE_KHR => {
                try self.recreateSwapChain();
                return;
            },
            else => return error.FailedToAcquireSwapChainImage,

        }

        self.updateUniformBuffer(self.currentFrame);

        _ = c.vkResetFences(self.device, 1, &self.inFlightFences[self.currentFrame]);

        _ = c.vkResetCommandBuffer(self.graphicsCommandBuffers[self.currentFrame], 0);
        try self.recordCommandBuffer(self.graphicsCommandBuffers[self.currentFrame], imageIndex);

        const waitSemaphores   = [_]c.VkSemaphore{self.imageAvailableSemaphores[self.currentFrame]};
        const waitStages       = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
        const signalSemaphores = [_]c.VkSemaphore{self.renderFinishedSemaphores[self.currentFrame]};
        const submitInfo:       c.VkSubmitInfo = .{
            .sType                = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
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
        if (c.vkQueueSubmit(self.graphicsQueue, 1, &submitInfo, self.inFlightFences[self.currentFrame]) != c.VK_SUCCESS) {
            return error.FailedToSubmitDrawCommandBuffer;
        }

        const swapChains                      = &[_]c.VkSwapchainKHR{self.swapChain};
        const presentInfo: c.VkPresentInfoKHR = .{
            .sType              = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores    = &signalSemaphores,
            .swapchainCount     = 1,
            .pSwapchains        = swapChains.ptr,
            .pImageIndices      = &imageIndex,
            .pResults           = null, // Optional
        };

        const result = c.vkQueuePresentKHR(self.presentQueue, &presentInfo);
        if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or self.framebufferResized) {
            self.framebufferResized = false;
            try self.recreateSwapChain();
        } else if (result != c.VK_SUCCESS) {
            return error.FailedToPresentSwapChainImage;
        }

        self.currentFrame = (self.currentFrame + 1) % MAX_FRAMES_IN_FLIGHT;
    }

    fn createShaderModule(self: *HelloTriangleApplication, code: []u8) !c.VkShaderModule {
        const createInfo: c.VkShaderModuleCreateInfo = .{
            .sType    = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = code.len,
            .pCode    = @ptrCast(@alignCast(code.ptr)),
        };

        var shaderModule: c.VkShaderModule = undefined;
        if (c.vkCreateShaderModule(self.device, &createInfo, null, &shaderModule) != c.VK_SUCCESS) {
            return error.FailedToCreateShaderModule;
        }

        return shaderModule;
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

    fn querySwapChainSupport(
        device:    c.VkPhysicalDevice,
        surface:   c.VkSurfaceKHR,
        allocator: *const std.mem.Allocator,
    ) !*SwapChainSupportDetails {
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

    fn isDeviceSuitable(
        device:    c.VkPhysicalDevice,
        surface:   c.VkSurfaceKHR,
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

        var supportedFeatures: c.VkPhysicalDeviceFeatures = undefined;
        c.vkGetPhysicalDeviceFeatures(device, &supportedFeatures);

        return familyIndices.isComplete()
            and swapChainAdequate
            and supportedFeatures.samplerAnisotropy == c.VK_TRUE;
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
        var familyIndices: QueueFamilyIndices = .{
            .graphicsFamily = null,
            .presentFamily  = null,
            .transferFamily = null,
        };

        var queueFamilyCount: u32 = 0;
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
        const queueFamilies       = try allocator.alloc(c.VkQueueFamilyProperties, queueFamilyCount);
        defer allocator.free(queueFamilies);
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);
        for (queueFamilies, 0..) |queueFamily, i| {
            // NOTE: The same queue family used for both drawing and presentation
            // would yield improved performance compared to this loop implementation
            // (even though it can happen in this implementation that the same queue family
            // gets selected for both). (2025-04-19)
            // IMPORTANT: There is no fallback for when the transfer queue family is not found
            // because the tutorial task requires a strictly transfer-only queue family (2025-06-04)

            if ((queueFamily.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) != 0) {
                familyIndices.graphicsFamily = @intCast(i);
            } else if ((queueFamily.queueFlags & c.VK_QUEUE_TRANSFER_BIT) != 0) {
                familyIndices.transferFamily = @intCast(i);
            }

            var doesSupportPresent: c.VkBool32 = 0;
            _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface, &doesSupportPresent);
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
        const glfwExtensions:   [*c][*c]const u8 = c.glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

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
        messageType:     c.VkDebugUtilsMessageTypeFlagsEXT,
        pCallbackData:   [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
        pUserData:       ?*anyopaque,
    ) callconv(.C) c.VkBool32 {
        _, _, _ = .{&messageSeverity, &messageType, &pUserData};
        std.debug.print("validation layer: {s}\n", .{pCallbackData.*.pMessage});

        return c.VK_FALSE;
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
    var gpa         = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app: HelloTriangleApplication = .{ .allocator = &allocator, .startTime = std.time.timestamp()};

    try app.run();
}
