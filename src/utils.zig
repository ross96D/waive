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
    return (avg_len - @min(avg_len, distf)) / avg_len;
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
