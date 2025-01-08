const std = @import("std");
const utils = @import("../utils.zig");
const password = @import("./password.zig");
const gtk = @import("gtk");

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
        return dir.makeOpenPath(".local/share/" ++ utils.APP_NAME, .{ .iterate = true });
    }
    var iter = env.iterator();
    while (iter.next()) |v| {
        std.debug.print("{s} {s}\n", .{ v.key_ptr.*, v.value_ptr.* });
    }
    std.log.err("no home variable found", .{});
    std.posix.exit(1);
}
pub const Storage = struct {
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

        const n = try file.write(encp);
        std.debug.assert(n == encp.len); // TODO add context
    }

    pub fn clip(self: Storage, namespace: []const u8) !bool {
        const file = self.dir.openFile(namespace, .{}) catch return false;
        defer file.close();

        const encpass = try file.readToEndAlloc(self.allocator, 1 << 28);
        defer self.allocator.free(encpass);

        const dest: [:0]u8 = try self.allocator.allocSentinel(u8, encpass.len, 0);
        defer {
            password.clean_mem(dest);
            self.allocator.free(dest);
        }
        const decp = password.decrypt(self.passphrase, dest, encpass);
        utils.text2clip(@ptrCast(decp.text));

        return true;
    }

    pub fn get_all_namespaces(self: Storage, allocator: std.mem.Allocator, list: *gtk.StringList) !void {
        var iter = self.dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                const data = try allocator.dupeZ(u8, entry.name);
                list.append(data);
            }
        }
    }
};
