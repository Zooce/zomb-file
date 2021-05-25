const std = @import("std");

const MAX_BUFFER_SIZE: usize = 4 * 1024; // 4k seems reasonable...

/// Token types
pub const TokenType = enum {
    // single character tokens
    Comma, Dollar, Dot, Equals,
    OpenCurly, OpenParen, OpenSquare,
    Newline, Number,
    CloseCurly, CloseParen, CloseSquare,
    Quote, WhiteSpace,

    // literals
    Comment, String,

    // others
    Error, Eof,
};

/// Token - We store only the starting offset and the size instead of slices because we don't want
/// to deal with carrying around pointers and all of the stuff that goes with that.
pub const Token = struct {
    const Self = @This();

    /// The offset into the file where this token begins.
    offset: usize = 0,

    /// The number of bytes in this token.
    size: usize = 0,

    /// The line in the file where this token was discovered. This is based on the number of
    /// newline tokens the Tokenizer has encountered. If the calling code has altered the cursor
    line: usize = undefined,

    /// The type of this token (duh)
    token_type: TokenType = TokenType.Error,
};

pub fn makeTokenizer(file: anytype) Tokenizer(@TypeOf(file)) {
    return .{ .file = file };
}

/// Tokenizes...nuf sed
pub fn Tokenizer(comptime FileType: type) type {
    return struct {
        // ---- Fields

        /// The file to read for tokenizing
        file: FileType,

        /// The buffer which the file's reader will read to
        buffer: [MAX_BUFFER_SIZE]u8 = undefined,

        /// The current number of bytes read into the buffer
        buffer_size: usize = 0,

        /// Where we are in the current buffer
        buffer_cursor: usize = 0,

        /// The starting index (wrt. whatever is being read) of the current token
        token_start: usize = 0,

        /// The token currently being discovered
        token: Token = undefined,

        /// The line where the current token lives (we start at the first line)
        current_line: usize = 1,

        // ---- Constant Definitions

        const Self = @This();

        // ---- Public Interface

        /// Get the next token
        pub fn next(self: *Self) !Token {
            self.token = Token{
                .offset = self.token_start,
                .line = self.current_line,
            };

            try self.fillBuffer();
            if (self.buffer_size == 0) {
                self.token.token_type = TokenType.Eof;
                return self.token;
            }

            const byte = self.consume().?;
            switch (byte) {
                // single-character tokens
                ',' => self.token.token_type = TokenType.Comma,
                '$' => self.token.token_type = TokenType.Dollar,
                '.' => self.token.token_type = TokenType.Dot,
                '=' => self.token.token_type = TokenType.Equals,
                '{' => self.token.token_type = TokenType.OpenCurly,
                '(' => self.token.token_type = TokenType.OpenParen,
                '[' => self.token.token_type = TokenType.OpenSquare,
                '}' => self.token.token_type = TokenType.CloseCurly,
                ')' => self.token.token_type = TokenType.CloseParen,
                ']' => self.token.token_type = TokenType.CloseSquare,
                '\n' => {
                    self.token.token_type = TokenType.Newline; // TODO: do we need this?
                    self.current_line += 1;
                },

                // multi-character tokens
                '\r' => {
                    if ((self.peek() orelse 0) == '\n') {
                        _ = self.consume();
                        self.token.token_type = TokenType.Newline; // TODO: do we need this?
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
                    self.token.token_type = TokenType.WhiteSpace; // TODO: do we need this?
                    _ = try self.whitespace();
                },

                // numbers
                '0' => {
                    try self.numberElseString();
                },
                '1'...'9' => {
                    try self.skipWhileInRange('0', '9');
                    try self.numberElseString();
                },

                else => try self.string(),
            }
            self.token_start += self.token.size;
            return self.token;
        }

        // ---- Multi-Character Token Parsing

        /// Parses a Comment token.
        fn comment(self: *Self) !void {
            self.token.token_type = TokenType.Comment;
            _ = try self.skipToBytes("\r\n"); // EOF is fine
        }

        /// Parses a String token.
        fn string(self: *Self) !void {
            self.token.token_type = TokenType.String;
            _ = try self.skipToBytes(" \t.,\r\n"); // EOF is fine
            // TODO: allow the above set of "skip-to" bytes to be escaped with '\' ?
        }

        /// Parses a WhiteSpace token.
        fn whitespace(self: *Self) !void {
            self.token.token_type = TokenType.WhiteSpace;
            _ = try self.skipWhileBytes(" \t"); // EOF is fine
        }

        /// Parses a quoted String token.
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
                        self.token.token_type = TokenType.String;
                        return;
                    },
                    else => unreachable,
                }
            }
            // if we're here, that's an error
            self.errorToken();
        }

        /// Parses a number if the buffer cursor points to a delimiter that would end a number,
        /// otherwise parses a string.
        fn numberElseString(self: *Self) !void {
            switch ((self.peek() orelse 0)) {
                ' ', '\t', '\r', '\n', ',', '.' => self.token.token_type = TokenType.Number,
                else => try self.string(),
            }
        }

        // ---- Common Token Generators

        fn errorToken(self: *Self) void {
            self.token.token_type = TokenType.Error;
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

                // If we're here, then we've exhausted our buffer and we need to refill it.
                try self.fillBuffer();
            }
        }

        /// Move the buffer cursor forward while it points to any byte in the specified, inclusive
        /// range. All bytes scanned are consumed, while the final byte (which is not within the
        /// specified range) is not.
        fn skipWhileInRange(self: *Self, lo: u8, hi: u8) !void {
            while (self.buffer_size > 0) {
                peekloop: while (self.peek()) |byte| {
                    if (byte >= lo and byte < hi) {
                        _ = self.consume();
                        continue :peekloop;
                    }
                    // The current byte is not in the specified range, so we stop here.
                    return;
                }

                // If we're here, then we've exhausted our buffer and we need to refill it.
                try self.fillBuffer();
            }
        }

        /// Checks to see if the buffer cursor is at the end of the buffer.
        fn bufferDepleted(self: Self) callconv(.Inline) bool {
            return self.buffer_cursor == self.buffer_size;
        }

        // ---- Buffer Operations

        /// Fill the buffer with some bytes from the file's reader if necessary.
        fn fillBuffer(self: *Self) !void {
            if (self.bufferDepleted()) {
                // TODO: Should we really have the file or can we get away with just the reader? If we only have the
                //       reader, then we have to account for a couple of things in the Token struct:
                //          1. The .offset field needs to be given to us by the caller of next(), since the caller will
                //             have control over the file's cursor directory (i.e. file.seekTo).
                //          2. For same reason as #1, recording the current line number in the Token struct may also be
                //             faulty, because the owner of the file may have skipped a newline with a manual seek.
                self.buffer_size = try self.file.reader().read(&self.buffer);
                self.buffer_cursor = 0;
            }
        }
    };
}

// ----  Testing

const testing = std.testing;

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
        if (self.cursor >= self.str.len or dest.len == 0) {
            return 0;
        }
        const size = std.math.min(dest.len, self.str.len);
        std.mem.copy(u8, dest, self.str[self.cursor..self.cursor + size]);
        self.cursor += size;
        return size;
    }

    fn reader(self: *Self) Reader {
        return .{ .context = self };
    }
};

const TestToken = struct {
    str: []const u8,
    line: usize,
    token_type: TokenType,
};

fn expectToken(test_token: TestToken, token: Token, orig_str: []const u8) !void {
    try testing.expectEqual(test_token.line, token.line);
    try testing.expectEqual(test_token.token_type, token.token_type);
    if (token.token_type == TokenType.Eof) {
        try testing.expectEqual(orig_str.len, token.offset);
        try testing.expectEqual(@as(usize, 0), token.size);

        // also make sure our test token is correct just to make sure
        try testing.expectEqualSlices(u8, "", test_token.str);
    }
    try testing.expectEqualSlices(u8, test_token.str, orig_str[token.offset..token.offset + token.size]);
}

fn doTokenTest(str: []const u8, test_tokens: []const TestToken) !void {
    var string_reader = StringReader.init(str);
    var tokenizer = makeTokenizer(string_reader);
    for (test_tokens) |token, i| {
        errdefer std.log.err("Token {} failed test.", .{ i });
        try expectToken(token, try tokenizer.next(), str);
    }
}

test "simple comment" {
    const str = "// this is a comment";
    const test_tokens = [_]TestToken{
        TestToken{ .str = str, .line = 1, .token_type = TokenType.Comment },
        TestToken{ .str = "", .line = 1, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &test_tokens);
}

// TODO: test complex comment - i.e. make sure no special Unicode characters mess this up

test "strings" {
    // IMPORTANT - this string is only for testing - it is not a valid zombie-file string
    const str = "I am.a,bunch\nstrings 01abc 123xyz";
    const test_tokens = [_]TestToken{
        TestToken{ .str = "I", .line = 1, .token_type = TokenType.String },
        TestToken{ .str = " ", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "am", .line = 1, .token_type = TokenType.String },
        TestToken{ .str = ".", .line = 1, .token_type = TokenType.Dot },
        TestToken{ .str = "a", .line = 1, .token_type = TokenType.String },
        TestToken{ .str = ",", .line = 1, .token_type = TokenType.Comma },
        TestToken{ .str = "bunch", .line = 1, .token_type = TokenType.String },
        TestToken{ .str = "\n", .line = 1, .token_type = TokenType.Newline },
        TestToken{ .str = "strings", .line = 2, .token_type = TokenType.String },
        TestToken{ .str = " ", .line = 2, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "01abc", .line = 2, .token_type = TokenType.String },
        TestToken{ .str = " ", .line = 2, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "123xyz", .line = 2, .token_type = TokenType.String },
        TestToken{ .str = "", .line = 2, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &test_tokens);
}

test "quoted string" {
    const str = "\"this is a \\\"quoted\\\" string\"";
    const test_tokens = [_]TestToken{
        TestToken{ .str = str, .line = 1, .token_type = TokenType.String },
        TestToken{ .str = "", .line = 1, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &test_tokens);
}

test "zeros" {
    // IMPORTANT - this string is only for testing - it is not a valid zombie-file string
    const str = "0 0\t0.0,0\r\n0\n";
    const test_tokens = [_]TestToken{
        TestToken{ .str = "0", .line = 1, .token_type = TokenType.Number },
        TestToken{ .str = " ", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "0", .line = 1, .token_type = TokenType.Number },
        TestToken{ .str = "\t", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "0", .line = 1, .token_type = TokenType.Number },
        TestToken{ .str = ".", .line = 1, .token_type = TokenType.Dot },
        TestToken{ .str = "0", .line = 1, .token_type = TokenType.Number },
        TestToken{ .str = ",", .line = 1, .token_type = TokenType.Comma },
        TestToken{ .str = "0", .line = 1, .token_type = TokenType.Number },
        TestToken{ .str = "\r\n", .line = 1, .token_type = TokenType.Newline },
        TestToken{ .str = "0", .line = 2, .token_type = TokenType.Number },
        TestToken{ .str = "\n", .line = 2, .token_type = TokenType.Newline },
    };
    try doTokenTest(str, &test_tokens);
}

// TODO: the following tests aren't really testing macros - move these to the parsing file

test "simple macro declaration" {
    const str =
        \\$name = "Zooce Dark"
        ;
    const test_tokens = [_]TestToken{
        TestToken{ .str = "$", .line = 1, .token_type = TokenType.Dollar },
        TestToken{ .str = "name", .line = 1, .token_type = TokenType.String },
        TestToken{ .str = " ", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "=", .line = 1, .token_type = TokenType.Equals },
        TestToken{ .str = " ", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "\"Zooce Dark\"", .line = 1, .token_type = TokenType.String },
        TestToken{ .str = "", .line = 1, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &test_tokens);
}

test "macro object declaration" {
    const str =
        \\$black_forground = {
        \\    foreground = #2b2b2b
        \\}
        ;
    const test_tokens = [_]TestToken{
        TestToken{ .str = "$", .line = 1, .token_type = TokenType.Dollar },
        TestToken{ .str = "black_forground", .line = 1, .token_type = TokenType.String },
        TestToken{ .str = " ", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "=", .line = 1, .token_type = TokenType.Equals },
        TestToken{ .str = " ", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "{", .line = 1, .token_type = TokenType.OpenCurly },
        TestToken{ .str = "\n", .line = 1, .token_type = TokenType.Newline },
        TestToken{ .str = "    ", .line = 2, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "foreground", .line = 2, .token_type = TokenType.String },
        TestToken{ .str = " ", .line = 2, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "=", .line = 2, .token_type = TokenType.Equals },
        TestToken{ .str = " ", .line = 2, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "#2b2b2b", .line = 2, .token_type = TokenType.String },
        TestToken{ .str = "\n", .line = 2, .token_type = TokenType.Newline },
        TestToken{ .str = "}", .line = 3, .token_type = TokenType.CloseCurly },
        TestToken{ .str = "", .line = 3, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &test_tokens);
}

test "macro array declaration" {
    const str =
        \\$ports = [ 8000, 8001, 8002 ]
        ;
    const test_tokens = [_]TestToken{
        TestToken{ .str = "$", .line = 1, .token_type = TokenType.Dollar },
        TestToken{ .str = "ports", .line = 1, .token_type = TokenType.String },
        TestToken{ .str = " ", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "=", .line = 1, .token_type = TokenType.Equals },
        TestToken{ .str = " ", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "[", .line = 1, .token_type = TokenType.OpenSquare },
        TestToken{ .str = " ", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "8000", .line = 1, .token_type = TokenType.Number },
        TestToken{ .str = ",", .line = 1, .token_type = TokenType.Comma },
        TestToken{ .str = " ", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "8001", .line = 1, .token_type = TokenType.Number },
        TestToken{ .str = ",", .line = 1, .token_type = TokenType.Comma },
        TestToken{ .str = " ", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "8002", .line = 1, .token_type = TokenType.Number },
        TestToken{ .str = " ", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "]", .line = 1, .token_type = TokenType.CloseSquare },
        TestToken{ .str = "", .line = 1, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &test_tokens);
}

test "macro with parameters declaration" {
    const str =
        \\$scope_def(scope, settings) = {
        \\    scope = $scope,
        \\\t settings = $settings
        \\}
        ;
    const test_tokens = [_]TestToken{
        TestToken{ .str = "$", .line = 1, .token_type = TokenType.Dollar },
        TestToken{ .str = "scope_def", .line = 1, .token_type = TokenType.String },
        TestToken{ .str = "(", .line = 1, .token_type = TokenType.OpenParen },
        TestToken{ .str = "scope", .line = 1, .token_type = TokenType.String },
        TestToken{ .str = ",", .line = 1, .token_type = TokenType.Comma },
        TestToken{ .str = " ", .line = 1, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "settings", .line = 1, .token_type = TokenType.String },
        TestToken{ .str = ")", .line = 2, .token_type = TokenType.CloseParen },
        TestToken{ .str = " ", .line = 2, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "=", .line = 2, .token_type = TokenType.Equals },
        TestToken{ .str = " ", .line = 2, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "{", .line = 2, .token_type = TokenType.OpenCurly },
        TestToken{ .str = "\n", .line = 2, .token_type = TokenType.Newline },
        TestToken{ .str = "    ", .line = 2, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "scope", .line = 2, .token_type = TokenType.String },
        TestToken{ .str = " ", .line = 3, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "=", .line = 3, .token_type = TokenType.Equals },
        TestToken{ .str = " ", .line = 3, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "$", .line = 3, .token_type = TokenType.Dollar },
        TestToken{ .str = "scope", .line = 3, .token_type = TokenType.String },
        TestToken{ .str = ",", .line = 3, .token_type = TokenType.Comma },
        TestToken{ .str = "\n", .line = 3, .token_type = TokenType.Newline },
        TestToken{ .str = "\t ", .line = 3, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "settings", .line = 4, .token_type = TokenType.String },
        TestToken{ .str = " ", .line = 4, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "=", .line = 4, .token_type = TokenType.Equals },
        TestToken{ .str = " ", .line = 4, .token_type = TokenType.WhiteSpace },
        TestToken{ .str = "$", .line = 4, .token_type = TokenType.Dollar },
        TestToken{ .str = "settings", .line = 4, .token_type = TokenType.String },
        TestToken{ .str = "\n", .line = 4, .token_type = TokenType.Newline },
        TestToken{ .str = "}", .line = 5, .token_type = TokenType.CloseCurly },
        TestToken{ .str = "", .line = 5, .token_type = TokenType.Eof },
    };
}
