const std = @import("std");
const json = std.json;

const buffer_size: usize = 4 * 1024; // 4k seems reasonable...
const ZombFileParser = @import("zomb").Parser(std.fs.File, buffer_size);

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

    var zomb_parser = ZombFileParser.init(&file);
    defer zomb_parser.deinit();

    // TODO: use zomb_parser to convert the .zomb file to a .json file

}