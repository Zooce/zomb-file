const std = @import("std");

const buffer_size: usize = 4 * 1024; // 4k seems reasonable...
const Tokenizer = @import("token.zig").Tokenizer(std.fs.File, buffer_size);

const ZombieError = error {
    InvalidArgument
};

pub fn main() anyerror!void {
    var file = fileblk: {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const alloc = &gpa.allocator;

        const args = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, args);

        if (args.len != 2) {
            std.log.err("Expected 1 argument, but found {}", .{args.len - 1});
            return ZombieError.InvalidArgument;
        }

        const file = try std.fs.cwd().openFile(args[1], .{ .read = true });
        std.log.info("Reading from {s}", .{args[1]});
        break :fileblk file;
    };

    var tokenizer = Tokenizer.init(&file);
    defer tokenizer.deinit();

    const token = try tokenizer.next();
}
