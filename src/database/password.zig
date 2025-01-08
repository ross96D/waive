const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;
const Aes = std.crypto.core.aes.Aes256;
const assert = std.debug.assert;

const Key = struct {
    data: [32]u8,
    fn create(key: *Key, passphrase: []const u8) void {
        Sha256.hash(passphrase, &key.data, .{});
    }
};

pub fn clean_mem(data: []u8) void {
    for (data) |*e| {
        e.* = 0;
    }
}

pub fn encrypted_size(len: usize) usize {
    const times: usize = len >> 4;
    if (len % 16 == 0) {
        return len;
    }
    return len + ((times + 1) << 4) - len;
}

test encrypted_size {
    try std.testing.expectEqual(16, encrypted_size(4));
    try std.testing.expectEqual(16, encrypted_size(16));
    try std.testing.expectEqual(32, encrypted_size(32));
    try std.testing.expectEqual(48, encrypted_size(33));
    try std.testing.expectEqual(96, encrypted_size(90));
}

pub fn encrypt(passphrase: []const u8, dst: []u8, password: []const u8) void {
    assert(dst.len == encrypted_size(password.len));

    var key: Key = undefined;
    Key.create(&key, passphrase);

    const enc = Aes.initEnc(key.data);
    var i: usize = 0;
    while (i + 16 < password.len) : (i += 16) {
        enc.encrypt(@ptrCast(dst[i .. i + 16]), @ptrCast(password[i .. i + 16]));
    }

    var buffer_src = std.mem.zeroes([16]u8);
    var buffer_dst = std.mem.zeroes([16]u8);
    const not_encrypted = password[i..];

    @memcpy(buffer_src[0..not_encrypted.len], not_encrypted);
    enc.encrypt(&buffer_dst, &buffer_src);
    @memcpy(dst[i..], buffer_dst[0..]);
}

const Decrypted = struct {
    text: []u8,
    cap: usize,
};

pub fn decrypt(passphrase: []const u8, dst: []u8, encrypted: []const u8) Decrypted {
    assert(dst.len == encrypted.len);

    var key: Key = undefined;
    Key.create(&key, passphrase);

    const dec = Aes.initDec(key.data);
    var i: usize = 0;
    while (i + 16 < encrypted.len) : (i += 16) {
        dec.decrypt(@ptrCast(dst[i .. i + 16]), @ptrCast(encrypted[i .. i + 16]));
    }

    var buffer_src = std.mem.zeroes([16]u8);
    var buffer_dst = std.mem.zeroes([16]u8);
    const not_decrypted = encrypted[i..];
    @memcpy(buffer_src[0..not_decrypted.len], not_decrypted);
    dec.decrypt(&buffer_dst, &buffer_src);
    @memcpy(dst[i..], buffer_dst[0..]);

    var length: usize = dst.len;
    while (dst[length - 1] == 0 and length > 0) : (length -= 1) {}

    return Decrypted{ .text = dst[0..length], .cap = dst.len };
}

test "encrypt_decrypt" {
    const passphrase = "123";
    const passwords = &[_][]const u8{
        "pass1" ** 22,  "12345789013921301",  "somethingelse",      "nothing to see",
        "arr*Zs.123;;", "12.2<><wwq~~!@kspa", "123;ax`2jds" ** 255,
    };

    var encrypteds = std.mem.zeroes([passwords.len][]u8);
    inline for (passwords, 0..) |pass, i| {
        const SIZE = comptime encrypted_size(pass.len);

        var tmp: [SIZE]u8 = std.mem.zeroes([SIZE]u8);
        encrypteds[i] = &tmp;

        encrypt(passphrase, encrypteds[i], pass);
    }

    var decrypteds: [passwords.len][]u8 = undefined;
    inline for (passwords, 0..) |pass, i| {
        const SIZE = comptime encrypted_size(pass.len);

        var tmp: [SIZE]u8 = std.mem.zeroes([SIZE]u8);
        decrypteds[i] = &tmp;

        const dec = decrypt(passphrase, decrypteds[i], encrypteds[i]);

        try std.testing.expectEqualSlices(u8, pass, dec.text);
    }
}
