//! What essentially maps to a direct c translation of a basic X11 window setup
//! for reference with vulkan compatibility included in initialization paramereters
const std = @import("std");
const vk = @import("vulkan");

const x11 = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
});


// c-style configuration of window parameters
const WindowParams = struct {
    x:              c_int,
    y:              c_int,
    width:          c_uint,
    height:         c_uint,
    border_width:   c_uint,
    // akin to z-index for draw ordering,
    depth:          c_int,
    // this mostly pertains to window input handling, for "vanilla" x11,
    // this can be either x11.InputOutput, x11.InputOnly, or x11.CopyFromParent.
    // Notably InputOnly windows, can perform no graphical output, hence the name InputOnly.
    // X11 extensions may define additional window classes, though I am not sure to what extent that
    // is present in a standard linux setup as of now.
    class:          c_uint,

    // Granular visual output properties, such as bit depth,  color mapping, essentially a surface format.
    // Generally, one simply inherits visuals from a parent window, which presumably at some point generates 
    // a visual property best suited for the physical screen.
    visual:        [*c]x11.Visual,

    attr_val_mask:  c_ulong,
    // window attributes
    win_attrs:      x11.XSetWindowAttributes,
};

/// A very barebones loader for linux based platforms...
/// Certainly doesn't cover all the cases and possibilities but works well enough
/// as an example
const BasicVulkanLoader = struct {
    var vk_lib: ?std.DynLib = null;
    var getInstanceProc: ?vk.PfnGetInstanceProcAddr = null;

    fn load(instance: vk.Instance, name: [*:0]const u8) ?*anyopaque {
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
            const func = vk_lib.?.lookup(*anyopaque, name_buf) orelse {
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
};

var vk_instance: vk.Instance = .null_handle;

var inst_proxy: vk.InstanceProxy = undefined;
var base_wrapper: vk.BaseWrapper = undefined;

pub fn main() !void {
    // a Display in X is a set of "screens" for a single user
    const main_display = x11.XOpenDisplay(0);


    // Top level  window in a windowing heirarchy, which covers the entirety
    // of a screen.
    const root_window  = x11.XDefaultRootWindow(main_display);

    std.debug.print("address of function: {*}\n", .{&x11.XOpenDisplay});
    
    // a Screen in X represents a physical monitor/hardware systems
    // In my case, there is 1 screen.
    // const screen       = x11.XDefaultScreen(main_display);

    // Very basic graphics context, if I were to hazard a guess, it's somewhat similar
    // to Win32's nasty GDI.
    // Just for reference -- vulkan is the only nightmare API I need
    // const gc_context   = x11.XDefaultGC(main_display, screen);
    var wp           = WindowParams{
        .x = 0,
        .y = 0,
        .width = 800,
        .height = 800,
        .border_width = 0,
        .depth = 0,
        .class = x11.CopyFromParent,
        .visual = x11.CopyFromParent,
        .attr_val_mask = x11.CWBackPixel | x11.CWEventMask,
        .win_attrs = .{
            // controls the default pixel color?? (idk for sure) 
            .background_pixel = 0xffff00aa,

            // which events should be intercepted by the window event loop.
            .event_mask = x11.StructureNotifyMask | x11.ExposureMask,
        }
    };

    const window       = x11.XCreateWindow(
        main_display,
        root_window,
        wp.x,
        wp.y,
        wp.width,
        wp.height,
        wp.border_width,
        wp.depth,
        wp.class,
        wp.visual,
        wp.attr_val_mask,
        &wp.win_attrs,
    );

    // map the window into the display heirarchy, with heirarchal position as specified
    // in XCreatWindow.
    _ = x11.XMapWindow(main_display, window);

    _ = x11.XStoreName(main_display, window, "Vulkan from X11 surface");

    // this is how the window server X communicates between clients, which includes window managers.
    // In this case, we retrieve the atom for the server's window destructor signal.
    // This way, our window will recieve and understand delete signals sent from other clients.
    // Apparently, this isn't strictly required, guh.
    const wm_delete_window = x11.XInternAtom(main_display, "WM_DELETE_WINDOW", x11.False);
    if (x11.XSetWMProtocols(main_display, window, wm_delete_window, 1) == 0) {
        std.debug.print("Error: Failed to register window manager's delete property!\n", .{});
    }

    while (true) {
        var event: x11.XEvent = undefined;
        _ = x11.XNextEvent(main_display, &event);

        switch (event.type) {
            x11.ClientMessage => {
                const client_event = event.xclient;
                if (@as(c_ulong, @intCast(client_event.data.l[0])) == wm_delete_window) {
                    _ = x11.XDestroyWindow(main_display, window);
                    break;
                } 
            },   
            else => {},
        }

        _ = x11.XClearWindow(main_display, window);

    }

    std.debug.print("Hello world\n", .{});
}
