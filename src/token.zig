const std = @import("std");

const expectEqual = std.testing.expectEqual;

const MAX_BUFFER_SIZE: usize = 4 * 1024;

pub fn makeTokenizer(reader: anytype) Tokenizer(@TypeOf(reader)) {
    return .{ .reader = reader };
}

/// Tokenizes...nuf sed
pub fn Tokenizer(comptime ReaderType: type) type {
    return struct {
        // ---- Fields

        /// The reader to use for tokenizing
        reader: ReaderType,

        /// The buffer which the reader will read to
        buffer: [MAX_BUFFER_SIZE]u8 = undefined,

        /// The current number of bytes read into the buffer
        buffer_size: usize = 0,

        /// The starting index of the current token
        token_start: u32 = 0,

        /// The line where the current token lives (we start at the first line)
        current_line: u32 = 1,

        /// The cursor (i.e. where we are in the current buffer)
        cursor: u32 = 0,

        // ---- Const Definitions

        const Self = @This();

        // ---- Public Interface

        /// Get the next token from the given reader
        pub fn nextToken(self: *Self) !Token {
            std.debug.print("> nextToken\n", .{});
            const token = tokenblk: {
                try self.fillBuffer();
                if (self.buffer_size == 0) {
                    break :tokenblk Token{ .line = self.current_line, .token_type = TokenType.EOF };
                }

                const byte = self.consume().?;
                switch (byte) {
                    // single-charachter tokens
                    ',' => break :tokenblk Token{ .offset = self.token_start, .size = 1, .line = self.current_line, .token_type = TokenType.COMMA },
                    '$' => break :tokenblk Token{ .offset = self.token_start, .size = 1, .line = self.current_line, .token_type = TokenType.DOLLAR },
                    '.' => break :tokenblk Token{ .offset = self.token_start, .size = 1, .line = self.current_line, .token_type = TokenType.DOT },
                    '=' => break :tokenblk Token{ .offset = self.token_start, .size = 1, .line = self.current_line, .token_type = TokenType.EQUAL },
                    '{' => break :tokenblk Token{ .offset = self.token_start, .size = 1, .line = self.current_line, .token_type = TokenType.LEFT_CURLY },
                    '(' => break :tokenblk Token{ .offset = self.token_start, .size = 1, .line = self.current_line, .token_type = TokenType.LEFT_PAREN },
                    '[' => break :tokenblk Token{ .offset = self.token_start, .size = 1, .line = self.current_line, .token_type = TokenType.LEFT_SQUARE },
                    '}' => break :tokenblk Token{ .offset = self.token_start, .size = 1, .line = self.current_line, .token_type = TokenType.RIGHT_CURLY },
                    ')' => break :tokenblk Token{ .offset = self.token_start, .size = 1, .line = self.current_line, .token_type = TokenType.RIGHT_PAREN },
                    ']' => break :tokenblk Token{ .offset = self.token_start, .size = 1, .line = self.current_line, .token_type = TokenType.RIGHT_SQUARE },

                    // multi-charactter tokens
                    '/' => {
                        if ((self.peek() orelse 0) == '/') {
                            break :tokenblk try self.comment();
                        } else {
                            break :tokenblk self.errorToken();
                        }
                    },
                    '"' => break :tokenblk try self.quoted_string(),


                    else => break :tokenblk self.errorToken(),
                }
            };
            self.token_start += token.size;
            return token;
        }

        // ---- Multi-Character Token Parsing

        /// Parses a COMMENT token, which is two forward slashes followed by any number of any charcter
        /// and ends when a NEWLINE is encountered.
        fn comment(self: *Self) !Token {
            std.debug.print("> comment\n", .{});
            var size: u32 = try self.skipToByte('\n');
            return Token{ .offset = self.token_start, .size = size, .line = self.current_line, .token_type = TokenType.COMMENT };
        }

        /// Parses a quoted string token.
        fn quoted_string(self: *Self) !Token {
            var size: u32 = 0;
            while(true) {
                size += try self.skipToByte('"');
                if ((self.peekPrev() orelse 0) != '\\') {
                    // consume the ending quote
                    _ = self.consume();
                    break;
                }
                // consume the escaped double-quote and keep going
                _ = self.consume();
            }

            if ((self.peek() orelse 0) != '"') {
                return self.errorToken();
            }
            return Token{ .offset = self.token_start, .size = size, .line = self.current_line, .token_type = TokenType.STRING };
        }

        // ---- Common Token Generators

        fn errorToken(self: Self) Token {
            return Token{ .line = self.current_line, .token_type = TokenType.ERROR };
        }

        // ---- Scanning Operations

        /// Advances the cursor to the next byte, consuming (and returning) the previous byte.
        /// If the cursor equals the buffer size, then this returns `null`.
        fn consume(self: *Self) ?u8 {
            if (self.bufferDepleted()) {
                return null;
            }
            self.cursor += 1;
            return self.buffer[self.cursor - 1];
        }

        /// Returns the byte at the cursor, or `null` if the cursor equals the buffer size.
        fn peek(self: Self) ?u8 {
            if (self.bufferDepleted()) {
                return null;
            }
            return self.buffer[self.cursor];
        }

        /// Returns the byte at the previous cursor, or `null` if either the cursor is 0
        /// or the buffer size is 0.
        fn peekPrev(self: Self) ?u8 {
            if (self.cursor == 0 or self.buffer_size == 0) {
                return null;
            }
            return self.buffer[self.cursor - 1];
        }

        /// Move the cursor forward until the target byte is found, and return the number of bytes
        /// skipped. All bytes leading to the target byte will be consumed, but the target byte will
        /// not be consumed.
        fn skipToByte(self: *Self, target: u8) !u32 {
            var skipped: u32 = 0;
            outer: while (self.buffer_size > 0) {
                while (self.peek()) |byte| {
                    if (byte == target) {
                        skipped += self.cursor;
                        break :outer;
                    }
                    _ = self.consume();
                }

                // If we're here, then we've scanned to the end of the buffer without finding the byte, so we need to
                // read more bytes into the buffer and keep going. Since we use the cursor to calculate token size, we
                // also need to accumulate its value since refilling the buffer will reset it.
                skipped += self.cursor;
                try self.fillBuffer();
            }
            return skipped;
        }

        /// Checks to see if the cursor is at the end of the buffer.
        fn bufferDepleted(self: Self) callconv(.Inline) bool {
            return self.cursor == self.buffer_size;
        }

        // ---- Buffer Operations

        /// Fill the buffer with some bytes from the reader if necessary.
        fn fillBuffer(self: *Self) !void {
            if (self.bufferDepleted()) {
                self.buffer_size = try self.reader.read(&self.buffer);
                self.cursor = 0;
            }
        }
    };
}

/// Token types
pub const TokenType = enum {
    // single character tokens
    COMMA, DOLLAR, DOT, EQUAL,
    LEFT_CURLY, RIGHT_CURLY,
    LEFT_PAREN, RIGHT_PAREN,
    LEFT_SQUARE, RIGHT_SQUARE,

    // literals
    COMMENT, STRING, VARIABLE,

    // others
    ERROR, EOF,
};

/// Token - We store only the offset and the token size instead of slices becuase
/// we don't want to deal with carrying around slices -- no need to store that kind
/// of memory.
pub const Token = struct {
    /// The offset into the file where this token begins (max = 4,294,967,295)
    offset: u32 = 0,

    /// The length of this token (max length = 4,294,967,295)
    size: u32 = 0,

    /// The line in the file where this token was discovered (max = 4,294,967,295)
    line: u32,

    /// The type of this token (duh)
    token_type: TokenType,
};


/// A string reader for testing.
const StringReader = struct {
    str: []const u8,
    cursor: usize,

    const Error = error{NoError};
    const Self = @This();
    const Reader = std.io.Reader(*Self, Error, read);

    fn init(str: []const u8) Self {
        return Self{
            .str = str,
            .cursor = 0,
        };
    }

    fn read(self: *Self, dest: []u8) Error!usize {
        if (self.str.len <= self.cursor or dest.len == 0) {
            return 0;
        }
        const size = std.math.min(self.str.len, dest.len);
        std.mem.copy(u8, dest, self.str[self.cursor..size]);
        self.cursor += size;
        return size;
    }

    fn reader(self: *Self) Reader {
        return .{ .context = self };
    }
};

test "comment token" {
    const str = "// this is a comment";
    var string_reader = StringReader.init(str);
    var tokenizer = makeTokenizer(string_reader.reader());

    var token = try tokenizer.nextToken();
    try expectEqual(@as(u32, 0), token.offset);
    try expectEqual(str.len, token.size);
    try expectEqual(@as(u32, 1), token.line);
    try expectEqual(TokenType.COMMENT, token.token_type);
}

test "quoted string token" {
    const str = "\"this is a string\"";
    var string_reader = StringReader.init(str);
    var tokenizer = makeTokenizer(string_reader.reader());

    var token = try tokenizer.nextToken();
    try expectEqual(@as(u32, 0), token.offset);
    try expectEqual(str.len, token.size);
    try expectEqual(@as(u32, 1), token.line);
    try expectEqual(TokenType.STRING, token.token_type);
}
