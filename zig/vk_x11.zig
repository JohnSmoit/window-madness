//! What essentially maps to a direct c translation of a basic X11 window setup
//! for reference with vulkan compatibility included in initialization paramereters
const std = @import("std");
const vk = @import("vulkan");

const DrawingSample = @import("DrawingSample.zig");

const x11 = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
});

// c-style configuration of window parameters
const WindowParams = struct {
    x: c_int,
    y: c_int,
    width: c_uint,
    height: c_uint,
    border_width: c_uint,
    // akin to z-index for draw ordering,
    depth: c_int,
    // this mostly pertains to window input handling, for "vanilla" x11,
    // this can be either x11.InputOutput, x11.InputOnly, or x11.CopyFromParent.
    // Notably InputOnly windows, can perform no graphical output, hence the name InputOnly.
    // X11 extensions may define additional window classes, though I am not sure to what extent that
    // is present in a standard linux setup as of now.
    class: c_uint,

    // Granular visual output properties, such as bit depth,  color mapping, essentially a surface format.
    // Generally, one simply inherits visuals from a parent window, which presumably at some point generates
    // a visual property best suited for the physical screen.
    visual: [*c]x11.Visual,

    attr_val_mask: c_ulong,
    // window attributes
    win_attrs: x11.XSetWindowAttributes,
};

const X11UserData = struct {
    window: x11.Window,
    dpy: *x11.Display,
};

fn initVulkanSurface(
    inst: *const vk.InstanceProxy,
    data: *const X11UserData,
) !vk.SurfaceKHR {
    return inst.createXlibSurfaceKHR(&vk.XlibSurfaceCreateInfoKHR{
        .window = data.window,
        .dpy = @ptrCast(data.dpy),
    }, null);
}

pub fn main() !void {
    // a Display in X is a set of "screens" for a single user
    const main_display = x11.XOpenDisplay(0);

    // Top level  window in a windowing heirarchy, which covers the entirety
    // of a screen.
    const root_window = x11.XDefaultRootWindow(main_display);

    std.debug.print("address of function: {*}\n", .{&x11.XOpenDisplay});

    // a Screen in X represents a physical monitor/hardware systems
    // In my case, there is 1 screen.
    // const screen       = x11.XDefaultScreen(main_display);

    // Very basic graphics context, if I were to hazard a guess, it's somewhat similar
    // to Win32's nasty GDI.
    // Just for reference -- vulkan is the only nightmare API I need
    // const gc_context   = x11.XDefaultGC(main_display, screen);
    var wp = WindowParams{
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
        },
    };

    const window = x11.XCreateWindow(
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
    var wm_delete_window = x11.XInternAtom(main_display, "WM_DELETE_WINDOW", x11.False);
    if (x11.XSetWMProtocols(main_display, window, &wm_delete_window, 1) == 0) {
        std.debug.print("Error: Failed to register window manager's delete property!\n", .{});
    }

    var vk_allocator = std.heap.DebugAllocator(.{ .safety = true }).init;
    defer {
        if (vk_allocator.deinit() == .leak) {
            std.debug.print("Oops, there were leaks\n", .{});
        } else {
            std.debug.print("No leaks detected\n", .{});
        }
    }

    var sample = try DrawingSample.init(
        *const X11UserData,
        vk_allocator.allocator(),
        initVulkanSurface,
        &X11UserData{
            .window = window,
            .dpy = main_display.?,
        },
    );
    defer sample.deinit(vk_allocator.allocator());

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
