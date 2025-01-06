const std = @import("std");
const gdk = @import("gdk");
const bultin = @import("builtin");

pub const APP_NAME = "waive";

var priv_env: ?std.process.EnvMap = null;
pub fn env() std.process.EnvMap {
    if (bultin.is_test) {
        if (priv_env == null) init(std.testing.allocator);
    }
    return priv_env.?;
}

pub fn init(allocator: std.mem.Allocator) void {
    priv_env = std.process.getEnvMap(allocator) catch unreachable;
}

pub fn text2clip(text: []const u8) void {
    const display = gdk.Display.getDefault().?;
    const clipboard = gdk.Display.getClipboard(display);
    clipboard.setText(text);
}

pub fn to_slice(data: [*:0]const u8) []u8 {
    var result: []u8 = undefined;
    result.ptr = @constCast(data);
    var i: usize = 0;
    while (data[i] != 0) : (i += 1) {}
    result.len = i;
    return result;
}
