const std = @import("std");
const storage = @import("database/storage.zig");

test "ref" {
    std.testing.refAllDecls(storage);
}
