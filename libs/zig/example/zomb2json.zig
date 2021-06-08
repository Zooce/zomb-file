//! zomb2json
//!
//! This program takes a .zomb file and converts it to a .json file.

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

        var path: []const u8 = undefined;
        if (args.len == 2) {
            path = args[1];
        } else {
            path = "../test.zomb";
        }

        const file = try std.fs.cwd().openFile(path, .{ .read = true });
        std.log.info("Reading from {s}", .{path});
        break :fileblk file;
    };

    var zomb_parser = ZombFileParser.init(&file);
    defer zomb_parser.deinit();

    try zomb_parser.parse();

    // TODO: const zomb_file = zomb_parser.parse();
    // TODO: convert `zomb_file` to a JSON file
}
