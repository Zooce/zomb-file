const std = @import("std");

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

        /// Where we are in the current buffer
        buffer_cursor: usize = 0,

        /// The starting index (wrt. whatever the reader is reading) of the current token
        token_start: usize = 0,

        /// The token currently being discovered
        token: Token = undefined,

        /// The line where the current token lives (we start at the first line)
        current_line: usize = 1,

        // ---- Const Definitions

        const Self = @This();

        // ---- Public Interface

        /// Get the next token from the given reader
        pub fn next(self: *Self) !Token {
            self.token = Token{
                .offset = self.token_start,
                .line = self.current_line,
            };

            try self.fillBuffer();
            if (self.buffer_size == 0) {
                self.token.token_type = TokenType.EOF;
                return self.token;
            }

            const byte = self.consume().?;
            switch (byte) {
                // single-character tokens
                ',' => self.token.token_type = TokenType.COMMA,
                '$' => self.token.token_type = TokenType.DOLLAR,
                '.' => self.token.token_type = TokenType.DOT,
                '=' => self.token.token_type = TokenType.EQUAL,
                '{' => self.token.token_type = TokenType.LEFT_CURLY,
                '(' => self.token.token_type = TokenType.LEFT_PAREN,
                '[' => self.token.token_type = TokenType.LEFT_SQUARE,
                '}' => self.token.token_type = TokenType.RIGHT_CURLY,
                ')' => self.token.token_type = TokenType.RIGHT_PAREN,
                ']' => self.token.token_type = TokenType.RIGHT_SQUARE,
                '\n' => {
                    self.token.token_type = TokenType.NEWLINE;
                    self.current_line += 1;
                },

                // multi-character tokens
                '\r' => {
                    if ((self.peek() orelse 0) == '\n') {
                        _ = self.consume();
                        self.token.token_type = TokenType.NEWLINE;
                        self.current_line += 1;
                    } else {
                        self.errorToken();
                    }
                },
                '"' => {
                    _ = try self.quoted_string();
                },
                '/' => {
                    if ((self.peek() orelse 0) == '/') {
                        try self.comment();
                    } else {
                        try self.string();
                    }
                },
                ' ', '\t' => {
                    self.token.token_type = TokenType.WHITESPACE;
                    _ = try self.whitespace();
                },

                else => try self.string(),
            }
            self.token_start += self.token.size;
            return self.token;
        }

        // ---- Multi-Character Token Parsing

        /// Parses a COMMENT token.
        fn comment(self: *Self) !void {
            self.token.token_type = TokenType.COMMENT;
            _ = try self.skipToBytes("\n"); // EOF is fine
        }

        /// Parses a STRING token.
        fn string(self: *Self) !void {
            self.token.token_type = TokenType.STRING;
            _ = try self.skipToBytes(" .,\n"); // EOF is fine
        }

        /// Parses a WHITESPACE token.
        fn whitespace(self: *Self) !void {
            self.token.token_type = TokenType.WHITESPACE;
            _ = try self.skipWhileBytes(" \t"); // EOF is fine
        }

        /// Parses a quoted STRING token.
        fn quoted_string(self: *Self) !void {
            while(try self.skipToBytes("\\\"")) {
                switch (self.peek().?) {
                    '\\' => {
                        // consume the escape byte and the byte it's escaping
                        _ = self.consume();
                        _ = self.consume();
                    },
                    '"' => {
                        // consume the ending double-quote and return
                        _ = self.consume();
                        self.token.token_type = TokenType.STRING;
                        return;
                    },
                    else => unreachable,
                }
            }
            // if we're here, that's an error
            self.errorToken();
        }

        // ---- Common Token Generators

        fn errorToken(self: *Self) void {
            self.token.token_type = TokenType.ERROR;
            self.token.size = 0;
        }

        // ---- Scanning Operations

        /// Consumes the current buffer byte (pointed to by the buffer cursor), which (in essence)
        /// adds it to the current token. If the buffer is depleted then this returns `null`
        /// otherwise it returns the consumed byte.
        fn consume(self: *Self) ?u8 {
            if (self.bufferDepleted()) {
                return null;
            }
            self.token.size += 1;
            self.buffer_cursor += 1;
            return self.buffer[self.buffer_cursor - 1];
        }

        /// Returns the byte at the buffer cursor, or `null` if the buffer cursor equals the buffer
        /// size.
        fn peek(self: Self) ?u8 {
            if (self.bufferDepleted()) {
                return null;
            }
            return self.buffer[self.buffer_cursor];
        }

        /// Move the buffer cursor forward until one of the target bytes is found. All bytes leading
        /// to the discovered target byte will be consumed, but that target byte will not be
        /// consumed. If we can't find any of the target bytes, we return `false` otherwise we
        /// return `true`.
        fn skipToBytes(self: *Self, targets: []const u8) !bool {
            while (self.buffer_size > 0) {
                while (self.peek()) |byte| {
                    for (targets) |target| {
                        if (byte == target) {
                            return true;
                        }
                    }
                    _ = self.consume();
                }

                // If we're here, then we've exhausted our buffer and we need to refill it so we can keep going.
                try self.fillBuffer();
            }
            // We didn't find any of the target bytes.
            return false;
        }

        /// Move the buffer cursor forward while one of the target bytes is found. All bytes scanned
        /// are consumed, while the final byte (which does not match any target byte) is not.
        fn skipWhileBytes(self: *Self, targets: []const u8) !void {
            while (self.buffer_size > 0) {
                peekloop: while (self.peek()) |byte| {
                    for (targets) |target| {
                        if (byte == target) {
                            _ = self.consume();
                            continue :peekloop;
                        }
                    }
                    // The byte we're looking at did not match any target, so return.
                    return;
                }

                // If we're here, then we've exhausted our buffer and we need to refill it so we can keep going.
                try self.fillBuffer();
            }
        }

        /// Checks to see if the buffer cursor is at the end of the buffer.
        fn bufferDepleted(self: Self) callconv(.Inline) bool {
            return self.buffer_cursor == self.buffer_size;
        }

        // ---- Buffer Operations

        /// Fill the buffer with some bytes from the reader if necessary.
        fn fillBuffer(self: *Self) !void {
            if (self.bufferDepleted()) {
                self.buffer_size = try self.reader.read(&self.buffer);
                self.buffer_cursor = 0;
            }
        }
    };
}

/// Token types
pub const TokenType = enum {
    // single character tokens
    COMMA, DOLLAR, DOT, EQUAL,
    LEFT_CURLY, LEFT_PAREN, LEFT_SQUARE,
    NEWLINE,
    RIGHT_CURLY, RIGHT_PAREN, RIGHT_SQUARE,
    QUOTE, WHITESPACE,

    // literals
    COMMENT, STRING,

    // others
    ERROR, EOF,
};

/// Token - We store only the starting offset and the size instead of slices because we don't want
/// to deal with carrying around pointers and all of the stuff that goes with that.
pub const Token = struct {
    const Self = @This();

    /// The offset into the file where this token begins (max = 4,294,967,295)
    offset: usize = 0,

    /// The number of bytes in this token (max length = 4,294,967,295)
    size: usize = 0,

    /// The line in the file where this token was discovered (max = 4,294,967,295)
    line: usize = undefined,

    /// The type of this token (duh)
    token_type: TokenType = TokenType.ERROR,
};

// ----  Testing

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

/// A string reader for testing.
const StringReader = struct {
    str: []const u8,
    cursor: usize,

    const Error = error{InvalidSeekIndex};
    const Self = @This();
    const Reader = std.io.Reader(*Self, Error, read);

    fn init(str: []const u8) Self {
        return Self{
            .str = str,
            .cursor = 0,
        };
    }

    fn seekTo(self: *Self, index: usize) !void {
        if (index > self.str.len) {
            return Error.InvalidSeekIndex;
        }
        self.cursor = index;
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

const TokenTester = struct {
    expectedSlice: []const u8,
    expectedOffset: usize,
    expectedLine: usize,
    expectedType: TokenType,

    const Self = @This();

    fn init(slice: []const u8, offset: usize, line: usize, token_type: TokenType) Self {
        return Self{
            .expectedSlice = slice,
            .expectedOffset = offset,
            .expectedLine = line,
            .expectedType = token_type,
        };
    }

    fn nextOffset(self: Self) usize {
        return self.expectedOffset + self.expectedSlice.len;
    }

    fn expect(self: Self, token: Token, str: []const u8) !void {
        try expectEqual(self.expectedOffset, token.offset);
        try expectEqual(self.expectedSlice.len, token.size);
        try expectEqual(self.expectedLine, token.line);
        try expectEqual(self.expectedType, token.token_type);
        try expectEqualSlices(u8, self.expectedSlice, str[token.offset..token.offset + token.size]);
    }
};

test "eof" {
    const str = "// comment";
    var string_reader = StringReader.init(str);
    var tokenizer = makeTokenizer(string_reader.reader());

    _ = try tokenizer.next(); // ignore the COMMENT token (there's already a test for these)
    var token = try tokenizer.next();
    try expectEqual(str.len, token.offset);
    try expectEqual(@as(usize, 0), token.size);
    try expectEqual(@as(usize, 1), token.line);
    try expectEqual(TokenType.EOF, token.token_type);
}

test "comment" {
    const str = "// this is a comment";
    var string_reader = StringReader.init(str);
    var tokenizer = makeTokenizer(string_reader.reader());

    var tester = TokenTester.init("// this is a comment", 0, 1, TokenType.COMMENT);
    var token = try tokenizer.next();
    try tester.expect(token, str);
}

test "quoted string" {
    const str = "\"this is a \\\"quoted\\\" string\"";
    var string_reader = StringReader.init(str);
    var tokenizer = makeTokenizer(string_reader.reader());

    var tester = TokenTester.init(str, 0, 1, TokenType.STRING);
    var token = try tokenizer.next();
    try tester.expect(token, str);
}

test "strings" {
    // IMPORTANT - this string is only for testing - it is not a valid zombie-file string
    const str = "I am.a,bunch\nstrings";
    var string_reader = StringReader.init(str);
    var tokenizer = makeTokenizer(string_reader.reader());

    var tester = TokenTester.init("I", 0, 1, TokenType.STRING);
    var token = try tokenizer.next();
    try tester.expect(token, str);

    tester = TokenTester.init(" ", tester.nextOffset(), 1, TokenType.WHITESPACE);
    token = try tokenizer.next();
    try tester.expect(token, str);

    tester = TokenTester.init("am", tester.nextOffset(), 1, TokenType.STRING);
    token = try tokenizer.next();
    try tester.expect(token, str);

    tester = TokenTester.init(".", tester.nextOffset(), 1, TokenType.DOT);
    token = try tokenizer.next();
    try tester.expect(token, str);

    tester = TokenTester.init("a", tester.nextOffset(), 1, TokenType.STRING);
    token = try tokenizer.next();
    try tester.expect(token, str);
    try tester.expect(token, str);

    tester = TokenTester.init(",", tester.nextOffset(), 1, TokenType.COMMA);
    token = try tokenizer.next();
    try tester.expect(token, str);

    tester = TokenTester.init("bunch", tester.nextOffset(), 1, TokenType.STRING);
    token = try tokenizer.next();
    try tester.expect(token, str);

    tester = TokenTester.init("\n", tester.nextOffset(), 1, TokenType.NEWLINE);
    token = try tokenizer.next();
    try tester.expect(token, str);

    tester = TokenTester.init("strings", tester.nextOffset(), 2, TokenType.STRING);
    token = try tokenizer.next();
    try tester.expect(token, str);
}
