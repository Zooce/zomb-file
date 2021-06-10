//! zomb2json
//!
//! This program takes a .zomb file and converts it to a .json file.

const std = @import("std");
const json = std.json;

const zomb = @import("zomb");


pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = &gpa.allocator;
    var file_contents = std.ArrayList(u8).init(alloc);
    defer file_contents.deinit();

    {
        const args = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, args);

        const path: []const u8 = if (args.len >= 2) args[1] else "../test.zomb";

        const file = try std.fs.cwd().openFile(path, .{ .read = true });
        defer file.close();
        std.log.info("Reading from {s}", .{path});

        const max_file_size = if (args.len >= 3) try std.fmt.parseUnsigned(usize, args[2], 10) else 100_000_000;

        try file.reader().readAllArrayList(&file_contents, max_file_size);
    }

    var zomb_parser = zomb.Parser.init(file_contents.items, alloc);
    defer zomb_parser.deinit();

    const z = try zomb_parser.parse();
    defer z.deinit();

    // TODO: const zomb_file = zomb_parser.parse();
    // TODO: convert `zomb_file` to a JSON file
}
