const std = @import("std");
const gdk = @import("gdk");
const gtk = @import("gtk");
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

pub fn text2clip(text: [:0]const u8) void {
    // const display = gdk.Display.getDefault().?;
    // const clipboard = gdk.Display.getClipboard(display);
    // clipboard.setText(text);
    var child = std.process.Child.init(&[_][]const u8{"wl-copy"}, @import("views.zig").allocator);
    child.stdin_behavior = .Pipe;
    child.spawn() catch |err| {
        switch (err) {
            inline else => |e| @panic("child.spawn" ++ @errorName(e)),
        }
    };
    _ = child.stdin.?.write(text) catch unreachable;
}

pub fn to_slice(data: [*:0]const u8) []u8 {
    var result: []u8 = undefined;
    result.ptr = @constCast(data);
    var i: usize = 0;
    while (data[i] != 0) : (i += 1) {}
    result.len = i;
    return result;
}

/// Optimal String Alignment Score
///
/// Is a Damerau-Levenshtein distance alghoritm but is not allowed to apply
/// multiple transformations on a same substring.
///
/// The result is transformed into an score of 0 to 1. Been 1 the highest
/// similarity
///
/// See: https://stats.stackexchange.com/a/467772
pub fn string_distance_score(allocator: std.mem.Allocator, s1: []const u8, s2: []const u8) !f32 {
    const s1_len = s1.len;
    const s2_len = s2.len;
    const avg_len: f32 = @as(f32, @floatFromInt(s1_len + s2_len)) / 2.0;

    var distance: usize = 0;
    {
        const INFINITY = s1_len + s2_len;

        const distances = try allocator.alloc([]usize, s1_len + 1);
        for (distances) |*d| {
            d.* = try allocator.alloc(usize, s2_len + 1);
            for (d.*) |*v| {
                v.* = INFINITY;
            }
        }

        var l_cost: usize = 0;
        for (0..s1_len) |i| {
            distances[i][0] = i;
        }
        for (0..s2_len) |i| {
            distances[0][i] = i;
        }

        for (1..s1_len + 1) |i| {
            for (1..s2_len + 1) |j| {
                if (s1[i - 1] == s2[j - 1]) {
                    l_cost = 0;
                } else {
                    l_cost = 1;
                }
                distances[i][j] = @min(
                    // delete
                    distances[i - 1][j] + 1,
                    @min(
                        // insert
                        distances[i][j - 1] + 1,
                        // substitution
                        distances[i - 1][j - 1] + l_cost,
                    ),
                );

                if ((i > 1) and (j > 1) and (s1[i - 1] == s2[j - 2]) and (s1[i - 2] == s2[j - 1])) {
                    distances[i][j] = @min(distances[i][j], distances[i - 2][j - 2] + l_cost);
                }
            }
        }
        distance = distances[s1_len][s2_len];

        for (distances) |d| {
            allocator.free(d);
        }
        allocator.free(distances);
    }

    const distf: f32 = @floatFromInt(distance);
    return ((avg_len - @min(avg_len, distf)) / avg_len) + (1 / (avg_len + 1));
}

/// Damerau-Levenshtein distance
pub fn string_distance(allocator: std.mem.Allocator, s1: [*:0]const u8, s2: [*:0]const u8) !usize {
    const s1_len = std.mem.len(s1);
    const s2_len = std.mem.len(s2);
    const INFINITY = s1_len + s2_len;

    const distances = try allocator.alloc([]usize, s1_len + 1);
    for (distances) |*d| {
        d.* = try allocator.alloc(usize, s2_len + 1);
        for (d.*) |*v| {
            v.* = INFINITY;
        }
    }

    var l_cost: usize = 0;
    for (0..s1_len) |i| {
        distances[i][0] = i;
    }
    for (0..s2_len) |i| {
        distances[0][i] = i;
    }

    for (1..s1_len + 1) |i| {
        for (1..s2_len + 1) |j| {
            if (s1[i - 1] == s2[j - 1]) {
                l_cost = 0;
            } else {
                l_cost = 1;
            }
            distances[i][j] = @min(
                // delete
                distances[i - 1][j] + 1,
                @min(
                    // insert
                    distances[i][j - 1] + 1,
                    // substitution
                    distances[i - 1][j - 1] + l_cost,
                ),
            );

            if ((i > 1) and (j > 1) and (s1[i - 1] == s2[j - 2]) and (s1[i - 2] == s2[j - 1])) {
                distances[i][j] = @min(distances[i][j], distances[i - 2][j - 2] + l_cost);
            }
        }
    }
    const result = distances[s1_len][s2_len];

    for (distances) |d| {
        allocator.free(d);
    }
    allocator.free(distances);

    return result;
}

test string_distance {
    try std.testing.expectEqual(1, try string_distance(std.testing.allocator, "st1", "st2"));
    try std.testing.expectEqual(1, try string_distance(std.testing.allocator, "st1", "s1t"));
    try std.testing.expectEqual(4, try string_distance(std.testing.allocator, "12345", "213000"));
}

pub fn set_widget_margin_all(widget: *gtk.Widget, margin: c_int) void {
    widget.setMarginStart(margin);
    widget.setMarginEnd(margin);
    widget.setMarginTop(margin);
    widget.setMarginBottom(margin);
}

pub fn Rc(T: type) type {
    return struct {
        const Self = @This();
        _count: usize,
        _allocator: std.mem.Allocator,
        value: T,

        pub fn init(allocator: std.mem.Allocator, value: T) *Self {
            const result = allocator.create(Self) catch unreachable;
            result.* = .{
                ._allocator = allocator,
                ._count = 1,
                .value = value,
            };
            return result;
        }

        pub fn ref(self: *Self) void {
            std.debug.assert(self._count > 0);
            self._count += 1;
        }

        pub fn unref(self: *Self) void {
            std.debug.assert(self._count > 0);
            self._count -= 1;
            if (self._count == 0) {
                self._allocator.destroy(self);
            }
        }
    };
}
