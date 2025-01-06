const std = @import("std");
const utils = @import("../utils.zig");
const password = @import("./password.zig");

fn data_directory() !std.fs.Dir {
    const env = utils.env();
    if (env.get("XDG_DATA_HOME")) |path| {
        var dir = try std.fs.openDirAbsolute(path, .{});
        defer dir.close();
        return dir.makeOpenPath(utils.APP_NAME, .{ .iterate = true });
    }
    if (env.get("HOME")) |path| {
        var dir = try std.fs.openDirAbsolute(path, .{});
        defer dir.close();
        return dir.makeOpenPath(utils.APP_NAME, .{ .iterate = true });
    }
    std.log.err("no home variable found", .{});
    std.posix.exit(1);
}
const Storage = struct {
    const StoreData = struct {
        namespace: []const u8,
        password: []const u8,
    };

    dir: std.fs.Dir,
    // TODO: should this be stored encrypted?
    passphrase: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(passphrase: []const u8, allocator: std.mem.Allocator) !Storage {
        return .{ .dir = try data_directory(), .passphrase = passphrase, .allocator = allocator };
    }

    pub fn initWithDir(dir: std.fs.Dir, passphrase: []const u8, allocator: std.mem.Allocator) Storage {
        return .{ .dir = dir, .passphrase = passphrase, .allocator = allocator };
    }

    pub fn store(self: Storage, data: StoreData) !void {
        const encp = try self.allocator.alloc(u8, password.encrypted_size(data.password.len));
        defer self.allocator.free(encp);

        password.encrypt(self.passphrase, encp, data.password);

        const file = try self.dir.createFile(data.namespace, .{ .truncate = true, .mode = 0o600 });
        // clean up on error
        errdefer self.dir.deleteFile(data.namespace) catch {};
        defer file.close();

        try file.write(encp);
    }

    pub fn clip(self: Storage, namespace: []const u8) !void {
        const file = try self.dir.openFile(namespace, .{});
        defer file.close();

        const encpass = try file.readToEndAlloc(self.allocator, 1 << 28);
        defer self.allocator.free(encpass);

        const dest = try self.allocator.alloc(u8, encpass.len);
        defer {
            password.clean_mem(dest);
            self.allocator.free(dest);
        }
        const decp = password.decrypt(self.passphrase, dest, encpass);
        utils.text2clip(decp.text);
    }

    pub fn get_all_namespaces(self: Storage, allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) !void {
        var iter = self.dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                try list.append(try allocator.dupe(u8, entry.name));
            }
        }
    }
};

test "get_all_namespaces" {
    const cwd = try std.fs.cwd().openDir(".", .{ .iterate = true });
    const storage = Storage.initWithDir(cwd, "123", std.testing.allocator);
    var list = std.ArrayList([]const u8).init(std.testing.allocator);
    defer list.deinit();
    try storage.get_all_namespaces(std.testing.allocator, &list);

    for (list.items) |item| {
        std.debug.print(" {*} name {s}\n", .{ item.ptr, item });
        std.testing.allocator.free(item);
    }
}