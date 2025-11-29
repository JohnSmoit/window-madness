//! Vulkan drawing sample
const vk = @import("vulkan");
const std = @import("std");

const log = std.log.scoped(.vulkan);

const Sample = @This();
const Allocator = std.mem.Allocator;

fn dbai(b: vk.DebugUtilsMessageSeverityFlagsEXT) u32 {
    return @bitCast(b);
}

fn debugCallback(
    flags: vk.DebugUtilsMessageSeverityFlagsEXT,
    msg_type: vk.DebugUtilsMessageTypeFlagsEXT,
    data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    user_data: ?*anyopaque,
) callconv(.c) vk.Bool32 {
    if (data) |dat| {
        const msg = dat.p_message orelse "(no message provided)";
        switch (dbai(flags)) {
            dbai(.{ .info_bit_ext = true }) => log.info("{s}", .{msg}),
            dbai(.{ .warning_bit_ext = true }) => log.warn("{s}", .{msg}),
            dbai(.{ .error_bit_ext = true }) => log.err("{s}", .{msg}),
            dbai(.{ .verbose_bit_ext = true }) => log.debug("{s}", .{msg}),
            else => log.debug("Oh fuck, something reaaaaaaaaaaaal bbad haappeened aaaaah", .{}),
        }
    } else {
        log.err("An unknown error occured", .{});
    }

    _ = user_data;
    _ = msg_type;

    return .true;
}
/// A very barebones loader for linux based platforms...
/// Certainly doesn't cover all the cases and possibilities but works well enough
/// as an example
const BasicVulkanLoader = struct {
    var vk_lib: ?std.DynLib = null;
    var getInstanceProc: ?vk.PfnGetInstanceProcAddr = null;

    pub fn load(instance: vk.Instance, name: [*:0]const u8) vk.PfnVoidFunction {
        if (vk_lib == null) {
            //TODO: Find a better way to control search paths for dll loaders
            const search_paths: []const [:0]const u8 = &.{
                "libvulkan.so",
                "/usr/lib64/libvulkan.so",
                "/usr/lib/libvulkan.so",
            };

            for (search_paths) |path| {
                vk_lib = std.DynLib.open(path) catch
                    continue;
                break;
            }

            if (vk_lib == null)
                @panic("Failed to load vulkan library. Ensure it is loaded and check search paths");
        }

        const name_buf: [:0]const u8 = std.mem.span(name);

        if (instance == .null_handle) {
            const func = vk_lib.?.lookup(vk.PfnVoidFunction, name_buf) orelse {
                std.debug.print("Failed to load function: {s}\n", .{name_buf});
                return null;
            };

            if (getInstanceProc == null and std.mem.eql(u8, name_buf, "vkGetInstanceProcAddr")) {
                getInstanceProc = @ptrCast(@alignCast(func));
            }

            return func;
        } else {
            std.debug.assert(getInstanceProc != null);
            std.debug.assert(vk_lib != null);

            return getInstanceProc.?(instance, name);
        }
    }

    pub fn cleanup() void {
        if (vk_lib) |*lib| {
            lib.close();
        }
    }
};

const WrapperTable = struct {
    instance: vk.InstanceWrapper,
    base: vk.BaseWrapper,
    device: vk.DeviceWrapper,
};

format_opts: FormatOptions = undefined,
present_opts: vk.PresentModeKHR = undefined,

inst: vk.InstanceProxy = undefined,
dev: vk.DeviceProxy = undefined,
wrappers: *WrapperTable = undefined,

h_inst: vk.Instance = .null_handle,
h_dev: vk.Device = .null_handle,
dbg_msg: vk.DebugUtilsMessengerEXT = .null_handle,

pdev: vk.PhysicalDevice = .null_handle,
surf: vk.SurfaceKHR = .null_handle,
swapchain: vk.SwapchainKHR = .null_handle,

present_queue: vk.Queue = .null_handle,
graphics_queue: vk.Queue = .null_handle,

pipeline: vk.Pipeline = .null_handle,
pipeline_layout: vk.PipelineLayout = .null_handle,
renderpass: vk.RenderPass = .null_handle,
desc_pool: vk.DescriptorPool = .null_handle,
desc: vk.DescriptorSet = .null_handle,
desc_layout: vk.DescriptorSetLayout = .null_handle,

cmd_pool: vk.CommandPool = .null_handle,
cmd_buf: vk.CommandBuffer = .null_handle,

acquire_fence: vk.Fence = .null_handle,
render_sem: vk.Semaphore = .null_handle,

fn initInstance(sample: *Sample) !void {
    sample.wrappers.base = vk.BaseWrapper.load(BasicVulkanLoader.load);

    const base = &sample.wrappers.base;

    const extensions: []const [*:0]const u8 = &.{
        vk.extensions.khr_surface.name.ptr,
        vk.extensions.khr_xlib_surface.name.ptr,
        vk.extensions.ext_debug_utils.name.ptr,
    };

    const layers: []const [*:0]const u8 = &.{
        "VK_LAYER_KHRONOS_validation",
    };

    sample.h_inst = try base.createInstance(&vk.InstanceCreateInfo{
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
        .enabled_layer_count = @intCast(layers.len),
        .pp_enabled_layer_names = layers.ptr,
        .p_application_info = &vk.ApplicationInfo{
            .api_version = @bitCast(vk.API_VERSION_1_4),
            .application_version = @bitCast(vk.makeApiVersion(0, 69, 420, 12)),
            .engine_version = 0,
            .p_application_name = "Partial J*b Application",
            .p_engine_name = "Larry Engine",
        },
        .p_next = &vk.DebugUtilsMessengerCreateInfoEXT{
            .message_severity = .{
                .info_bit_ext = true,
                .warning_bit_ext = true,
                .error_bit_ext = true,
                .verbose_bit_ext = true,
            },
            .message_type = .{
                .validation_bit_ext = true,
                .general_bit_ext = true,
            },
            .pfn_user_callback = debugCallback,
        },
    }, null);

    sample.wrappers.instance = vk.InstanceWrapper.load(sample.h_inst, BasicVulkanLoader.load);
    sample.inst = vk.InstanceProxy.init(sample.h_inst, &sample.wrappers.instance);

    sample.dbg_msg = try sample.inst.createDebugUtilsMessengerEXT(&vk.DebugUtilsMessengerCreateInfoEXT{
        .message_severity = .{
            .info_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true,
            .verbose_bit_ext = true,
        },
        .message_type = .{
            .validation_bit_ext = true,
            .general_bit_ext = true,
        },
        .pfn_user_callback = debugCallback,
    }, null);

    const test_msg: [*:0]const u8 =
        \\vkCreateInstance():  
        \\ What the fuck did you just fucking pass to me, you little bitch? I'll have you know I graduated top of my class in the Navy Seals, and I've been involved in numerous secret raids on Al-Quaeda, and I have over 300 confirmed kills. I am trained in gorilla warfare and I'm the top sniper in the entire US armed forces. You are nothing to me but just another target. I will wipe you the fuck out with precision the likes of which has never been seen before on this Earth, mark my fucking words. You think you can get away with passing that shit to me over the c ABI? Think again, fucker. As we speak I am contacting my secret network of spies across the USA and your IP is being traced right now so you better prepare for the storm, maggot. The storm that wipes out the pathetic little thing you call your life. You're fucking dead, kid. I can be anywhere, anytime, and I can kill you in over seven hundred ways, and that's just with my bare hands. Not only am I extensively trained in unarmed combat, but I have access to the entire arsenal of the United States Marine Corps and I will use it to its full extent to wipe your miserable ass off the face of the continent, you little shit. If only you could have known what unholy retribution your little "clever" argument was about to bring down upon you, maybe you would have held your fucking vim macro. But you couldn't, you didn't, and now you're paying the price, you goddamn idiot. I will shit fury all over you and you will drown in it. You're fucking dead, kiddo.
        \\The Vulkan spec states: vkCreateInstance shall reserve all rights to criticize, abuse, or otherwise harm, kill, or offend the user should they make a particularly stupid decision, as it is often not enough to merely terminate user program ungracefully. (https://docs.vulkan.org/spec/latest/chapters/VK_Instance/foobared.html#VUID-VkInstanceCreateInfo-ass-01314)
    ;

    sample.inst.submitDebugUtilsMessageEXT(
        .{ .error_bit_ext = true },
        .{ .general_bit_ext = true },
        &vk.DebugUtilsMessengerCallbackDataEXT{
            .message_id_number = 0x69,
            .p_message = test_msg,
        },
    );
}

const max_device_size = 64;

fn validateDeviceExtensions(
    sample: *Sample, 
    pdev: vk.PhysicalDevice, 
    allocator: Allocator, 
    exts: []const [*:0]const u8
) bool {
    const supported_exts = sample.inst.enumerateDeviceExtensionPropertiesAlloc(
        pdev,
        null,
        allocator,
    ) catch |err| {
        log.warn("Failed to enumerate extensions: {t}", .{err});
        return false;
    };
    defer allocator.free(supported_exts);

    for (exts) |ext| {
        log.info("Needed extension: {s}\n", .{ext});
    }

    for (exts) |needed| {
        var supported = false;
        for (supported_exts) |ext| {
            if (std.mem.orderZ(u8, @ptrCast(&ext.extension_name), needed) == .eq) {
                supported = true;
                break;
            }
        }

        if (!supported)
            return false;
    }

    return true;
}

const QueueIndices = struct {
    graphics: usize,
    present: usize,
    compute: usize,
};

fn checkDeviceQueueSupport(
    sample: *Sample,
    dev: vk.PhysicalDevice,
    allocator: Allocator,
) ?QueueIndices {
    const props = sample.inst.getPhysicalDeviceQueueFamilyPropertiesAlloc(dev, allocator) catch |err| {
        log.warn("failed to get device queue properties: {t}\n", .{err});
        return null;
    };
    defer allocator.free(props);

    var present_index: ?usize = null;
    var graphics_index: ?usize = null;
    var compute_index: ?usize = null;

    for (props, 0..) |fam, i| {
        log.info("Queue family {d}: Supports {f}", .{ i, fam.queue_flags });

        if (graphics_index == null and fam.queue_flags.contains(.{ .graphics_bit = true }))
            graphics_index = i;
        if (compute_index == null and fam.queue_flags.contains(.{ .compute_bit = true }))
            compute_index = i;

        const present_support =
            sample.inst.getPhysicalDeviceSurfaceSupportKHR(dev, @intCast(i), sample.surf) catch |err| {
                log.warn("Failed to get surface support capabilities for device queue: {t}", .{err});
                return null;
            };

        if (present_index == null and present_support != .true)
            present_index = i;
    }

    if (present_index == null or graphics_index == null or compute_index == null)
        return null;

    return QueueIndices{
        .compute  = compute_index.?,
        .graphics = graphics_index.?,
        .present  = present_index.?,
    };
}

// this'd probably make more sense
// if the caller could actually choose a list of formats
// but whatever...
const FormatOptions = struct {
    format: vk.Format,
    colorspace: vk.ColorSpaceKHR,
};

fn checkDeviceFormats(
    sample: *Sample, 
    dev: vk.PhysicalDevice, 
    allocator: Allocator
) ?FormatOptions {
    const supported_formats = sample.inst.getPhysicalDeviceSurfaceFormatsAllocKHR(
        dev,
        sample.surf,
        allocator,
    ) catch |err| {
        log.warn("Failed to get supported surface formats: {t}", .{err});
        return null;
    };
    defer allocator.free(supported_formats);

    // NOTE: These'll need to be lists arraged in order of priority in order
    // for this to really work well cross platform...
    const requested_format     = .b8g8r8a8_srgb;
    const requested_colorspace = .srgb_nonlinear_khr;

    for (supported_formats) |format| {
        if (format.format == requested_format and format.color_space == requested_colorspace) 
            return FormatOptions{
                .format     = requested_format,
                .colorspace = requested_colorspace,
            };
    }

    return null;
}

fn checkDevicePresentModes(
    sample: *Sample, 
    dev: vk.PhysicalDevice, 
    allocator: Allocator,
) ?vk.PresentModeKHR {
    const present_modes = sample.inst.getPhysicalDeviceSurfacePresentModesAllocKHR(
        dev,
        sample.surf,
        allocator,
    ) catch |err| {
        log.debug("Failed to get present modes: {t}", .{err});
        return null;
    };

    const requested_present = .fifo_khr; 
    for (present_modes) |mode| {
        if (mode == requested_present)
            return mode;
    }

    return null;
}

fn pickDevice(sample: *Sample, allocator: Allocator) !void {
    var devices: [max_device_size]vk.PhysicalDevice = undefined;
    // validate device-level extensions exist
    var device_count: u32 = undefined;
    _ = try sample.inst.enumeratePhysicalDevices(&device_count, null);

    if (device_count == 0) {
        log.err("No GPU's, virtual or otherwise detected -- maybe try downloading more?\n", .{});
        return error.NoVulkanDevices;
    }

    _ = try sample.inst.enumeratePhysicalDevices(&device_count, &devices);

    const device_extensions: []const [*:0]const u8 = &.{
        vk.extensions.khr_swapchain.name,
    };

    for (devices[0..device_count]) |dev| {
        const props = sample.inst.getPhysicalDeviceProperties(dev);
        log.debug("Checking device: {s}...\n", .{props.device_name});

        if (!sample.validateDeviceExtensions(dev, allocator, device_extensions)) {
            log.debug("...Rejected (Reason: missing extension)", .{});
            continue;
        }

        const queue_indices = sample.checkDeviceQueueSupport(dev, allocator) orelse {
            log.debug("...Rejected (Reason: missing queue operation support)", .{});
            continue;
        };
        const format_opts = sample.checkDeviceFormats(dev, allocator) orelse {
            log.debug("...Rejected (Reason: missing required format option)", .{});
            continue;
        };
        const present_opts = sample.checkDevicePresentModes(dev, allocator) orelse {
            log.debug("...Rejected (Reason: missing required presentation option)", .{});
            continue;
        };

        log.debug("...Acccepted!", .{});

        sample.format_opts = format_opts;
        sample.present_opts = present_opts;

        const priorities: [*]const f32 = &.{1.0};
        // TODO: (Optional): collapse queue indicies into singular queues and preserve mappings between
        // queue features and actual queue handles since some queues like compute might share indices
        // with graphics queues except in the case of a dedicated compute queue (which I'm pretty sure
        // my GPU has, but my selection algorithm is basic and probably misses it).
        sample.h_dev = try sample.inst.createDevice(dev, &vk.DeviceCreateInfo{
            .enabled_extension_count = device_extensions.len,
            .pp_enabled_extension_names = device_extensions.ptr,
            .p_enabled_features = null, 
            .queue_create_info_count = 2,
            .p_queue_create_infos = &[_]vk.DeviceQueueCreateInfo{
                .{
                    .queue_count = 1,
                    .p_queue_priorities = priorities,
                    .queue_family_index = @intCast(queue_indices.graphics),
                },
                .{
                    .queue_count = 1,
                    .p_queue_priorities = priorities,
                    .queue_family_index = @intCast(queue_indices.present),
                },
            },
        }, null);
    }
}

fn createMainSwapchain(sample: *Sample) !void {
    _ = sample;
}

pub fn init(
    comptime UT: type,
    allocator: Allocator,
    surfaceInitFunc: *const fn (*const vk.InstanceProxy, UT) anyerror!vk.SurfaceKHR,
    user_data: UT,
) !Sample {
    var sample: Sample = .{};

    errdefer sample.deinit(allocator);
    // allocate some memory
    sample.wrappers = try allocator.create(WrapperTable);

    try sample.initInstance();
    sample.surf = try surfaceInitFunc(&sample.inst, user_data);

    var temp_arena = std.heap.ArenaAllocator.init(allocator);
    defer temp_arena.deinit();

    try sample.pickDevice(temp_arena.allocator());
    try sample.createMainSwapchain();

    return sample;
}

pub fn deinit(sample: *Sample, allocator: Allocator) void {
    allocator.destroy(sample.wrappers);
}
