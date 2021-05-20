const std = @import("std");
const Tokenizer = @import("scanner.zig").Tokenizer;

const MAX_READ_LEN: usize = 100;

const ZombieError = error {
    InvalidArgument
};

pub fn main() anyerror!void {
    const file = fileblk: {
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
    defer file.close(); // TODO: can we do this earlier?

    var buffer: [MAX_READ_LEN]u8 = undefined;
    var line = (try file.reader().readUntilDelimiterOrEof(&buffer, '\n')) orelse null;
    if (line) |l| {
        std.log.info("Line: {s}", .{l});
    }
    try file.seekTo(0);
    line = (try file.reader().readUntilDelimiterOrEof(&buffer, '\n')) orelse null;
    if (line) |l| {
        std.log.info("Line: {s}", .{l});
    }

    var tokenizer = Tokenizer{ .reader = file.reader() };
    const token = try tokenizer.nextToken();

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const alloc = &gpa.allocator;
    // var tokens = std.ArrayList(Token).init(alloc);
    // defer tokens.deinit();

    // var scanner = Scanner{ .reader = file.reader() };

    // var buffer: [MAX_READ_LEN]u8 = undefined;
    // scanloop: while(true) {
    //     if (readLine(reader, &buffer)) |line| {
    //         std.log.info("> {s}", .{line});
    //     } else {
    //         break :scanloop;
    //     }
    // }

    // TODO: traverse AST and do variable substitution

    // TODO: write AST to a JSON file
}
