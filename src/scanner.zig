const std = @import("std");

pub fn Scanner(comptime FileType_: type, max_buffer_size_: anytype) type {
    return struct {

        const Self = @This();

        const TestData = struct {
            read_count: usize = 0,
        };

        /// The file to read for scanning -- we own this for the following reasons:
        ///     1. The .offset field of a Token is based on where we are in the file. If some other
        ///        code owns the file, they have control over the file's underlying cursor from
        ///        calls like `file.seekTo`. We want control over the file's underlying cursor, thus
        ///        we want to own the file itself.
        ///     2. For same reason as #1, the current line number may also be faulty if some other
        ///        code owns the file and seeks past one or more newlines before the scanner does
        ///        another read.
        file: *FileType_,

        /// Where we are in the file
        file_cursor: usize = 0,

        /// The reader for the file
        reader: typeblk: {
            inline for (@typeInfo(FileType_).Struct.decls) |decl| {
                if (std.mem.eql(u8, "reader", decl.name)) {
                    break :typeblk decl.data.Fn.return_type;
                }
            }
            @compileError("Unable to get reader type for Scanner");
        },

        /// The buffer which the file's reader will read to
        buffer: [max_buffer_size_]u8 = undefined,

        /// The current number of bytes read into the buffer
        buffer_size: usize = 0,

        /// Where we are in the current buffer
        buffer_cursor: usize = 0,

        /// Whether we've already encountered EOF - so we can skip unnecessary syscalls
        eof_in_buffer: bool = false,

        /// The line where the current token lives (we start at the first line)
        current_line: usize = 1,

        test_data: TestData = TestData{},

        pub fn init(file_: *FileType_) Self {
            return Self{
                .file = file_,
                .reader = file_.reader(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.file.close();
        }

        /// Ensures that there are bytes in the buffer and advances the file and buffer cursors
        /// forward by one byte. If there are no more bytes to read from then this returns `null`
        /// otherwise it returns the byte previously pointed to by the buffer cursor.
        pub fn advance(self: *Self) ?u8 {
            if (!self.ensureBufferHasBytes()) {
                return null;
            }

            self.file_cursor += 1;
            self.buffer_cursor += 1;

            const byte = self.buffer[self.buffer_cursor - 1];
            if (byte == '\n') self.current_line += 1;
            return byte;
        }

        /// Returns the byte at the buffer cursor, or `null` if the buffer cursor equals the buffer
        /// size.
        pub fn peek(self: *Self) ?u8 {
            if (!self.ensureBufferHasBytes()) {
                return null;
            }
            return self.buffer[self.buffer_cursor];
        }

        pub fn peekNext(self: *Self) ?u8 {
            if (!self.ensureBufferHasBytes() or self.buffer_cursor + 1 == self.buffer_size) {
                return null;
            }
            return self.buffer[self.buffer_cursor + 1];
        }

        /// Fill the buffer with some bytes from the file's reader if necessary, and report whether
        /// there bytes left to read.
        fn ensureBufferHasBytes(self: *Self) bool {
            if (self.buffer_cursor == self.buffer_size and !self.eof_in_buffer) {
                if (self.reader.read(&self.buffer)) |count| {
                    self.buffer_size = count;
                } else |err| {
                    std.log.err("Encountered error while reading: {}", .{err});
                    self.buffer_size = 0;
                }
                self.buffer_cursor = 0;
                self.eof_in_buffer = self.buffer_size < max_buffer_size_;
                self.test_data.read_count += 1;
            }
            return self.buffer_cursor < self.buffer_size;
        }
    };
}

//==============================================================================
//
//
//
// Testing
//==============================================================================

const testing = std.testing;
const StringReader = @import("testing/string_reader.zig").StringReader;

const max_buffer_size: usize = 5;
const StringScanner = Scanner(StringReader, max_buffer_size);

test "scanner" {
    const str =
        \\Hello,
        \\ World!
    ;
    var string_reader = StringReader{ .str = str };
    var scanner = StringScanner.init(&string_reader);
    defer scanner.deinit();

    try testing.expectEqual(@as(usize, 0), scanner.test_data.read_count);
    try testing.expectEqual(@as(usize, 1), scanner.current_line);
    try testing.expectEqual(false, scanner.eof_in_buffer);
    try testing.expectEqual(@as(u8, 'H'), scanner.advance().?);
    try testing.expectEqual(@as(u8, 'e'), scanner.advance().?);
    try testing.expectEqual(@as(u8, 'l'), scanner.advance().?);
    try testing.expectEqual(@as(u8, 'l'), scanner.advance().?);
    try testing.expectEqual(@as(u8, 'o'), scanner.advance().?);
    try testing.expectEqual(@as(usize, 1), scanner.test_data.read_count);
    try testing.expectEqual(@as(usize, 1), scanner.current_line);
    try testing.expectEqual(false, scanner.eof_in_buffer);
    try testing.expectEqual(@as(u8, ','), scanner.peek().?);
    try testing.expectEqual(@as(u8, '\n'), scanner.peekNext().?);
    try testing.expectEqual(@as(u8, ','), scanner.advance().?);
    try testing.expectEqual(@as(u8, '\n'), scanner.advance().?);
    try testing.expectEqual(@as(u8, ' '), scanner.advance().?);
    try testing.expectEqual(@as(u8, 'W'), scanner.advance().?);
    try testing.expectEqual(@as(u8, 'o'), scanner.advance().?);
    try testing.expectEqual(@as(usize, 2), scanner.test_data.read_count);
    try testing.expectEqual(@as(usize, 2), scanner.current_line);
    try testing.expectEqual(false, scanner.eof_in_buffer);
    try testing.expectEqual(@as(u8, 'l'), scanner.peekNext().?);
    try testing.expectEqual(@as(u8, 'r'), scanner.advance().?);
    try testing.expectEqual(@as(u8, 'l'), scanner.advance().?);
    try testing.expectEqual(@as(u8, 'd'), scanner.advance().?);
    try testing.expectEqual(@as(u8, '!'), scanner.advance().?);
    try testing.expectEqual(@as(usize, 3), scanner.test_data.read_count);
    try testing.expectEqual(@as(usize, 2), scanner.current_line);
    try testing.expectEqual(true, scanner.eof_in_buffer);
    try testing.expectEqual(@as(?u8, null), scanner.peek());
    try testing.expectEqual(@as(?u8, null), scanner.peekNext());
    try testing.expectEqual(@as(?u8, null), scanner.advance());
    try testing.expectEqual(@as(usize, 3), scanner.test_data.read_count);
    try testing.expectEqual(@as(usize, 2), scanner.current_line);
    try testing.expectEqual(true, scanner.eof_in_buffer);
}
