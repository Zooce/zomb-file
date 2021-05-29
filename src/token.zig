const std = @import("std");

const max_buffer_size: usize = 4 * 1024; // 4k seems reasonable...

/// These are the delimiters that will be used as tokens.
const TokenDelimiter = enum(u8) {
    Dollar = '$', // 0x24  36
    OpenParen = '(', // 0x28  40
    CloseParen = ')', // 0x29  41
    Comma = ',', // 0x2C  44
    Dot = '.', // 0x2E  46
    Equals = '=', // 0x3D  61
    OpenSquare = '[', // 0x5B  91
    CloseSquare = ']', // 0x5D  93
    OpenCurly = '{', // 0x7B  123
    CloseCurly = '}', // 0x7D  125
};

/// These are the delimiters that will NOT be used as tokens.
const NonTokenDelimiter = enum(u8) {
    Tab = '\t', // 0x09  9
    LineFeed = '\n', // 0x0A  10
    CarriageReturn = '\r', // 0x0D  13
    Space = ' ', // 0x20  32
    Quote = '"', // 0x22  24
    ReverseSolidus = '\\', // 0x5C  92
};

/// A enum that represents all individual delimiters (regardless of their use as actual tokens).
const Delimiter = @Type(blk: {
    const fields = @typeInfo(TokenDelimiter).Enum.fields
        ++ @typeInfo(NonTokenDelimiter).Enum.fields
        ++ &[_]std.builtin.TypeInfo.EnumField{ .{ .name = "None", .value = 0 } };

    break :blk .{
        .Enum = .{
            .layout = .Auto,
            .tag_type = u8,
            .decls = &[_]std.builtin.TypeInfo.Declaration{},
            .fields = fields,
            .is_exhaustive = true,
        },
    };
});

/// Since we need to iterate through the delimiters sometimes, we have this slice of them.
const delimiters = blk: {
    var delims: []const u8 = &[_]u8{};
    inline for (std.meta.fields(Delimiter)) |d| {
        if (d.value > 0) { // ignore the None field
            delims = delims ++ &[_]u8{d.value};
        }
    }
    break :blk delims;
};

/// Special token types (usually a combination of Delimiters)
const SpecialToken = enum(u8) {
    Eof = 0,
    Range,
    Newline,
    Comment,
    String,
    Number,
};

pub const TokenType = @Type(out: {
    const fields = @typeInfo(SpecialToken).Enum.fields ++ @typeInfo(TokenDelimiter).Enum.fields;
    break :out .{
        .Enum = .{
            .layout = .Auto,
            .tag_type = u8,
            .decls = &[_]std.builtin.TypeInfo.Declaration{},
            .fields = fields,
            .is_exhaustive = true,
        },
    };
});

/// Token - We store only the starting offset and the size instead of slices because we don't want
/// to deal with carrying around pointers and all of the stuff that goes with that.
pub const Token = struct {
    /// The offset into the file where this token begins.
    offset: usize = 0,

    /// The number of bytes in this token.
    size: usize = 0,

    /// The line in the file where this token was discovered. This is based on the number of
    /// newline tokens the Tokenizer has encountered. If the calling code has altered the cursor
    line: usize = undefined,

    /// The type of this token (duh)
    token_type: TokenType = undefined,
};

pub const TokenizerError = error{
    InvalidControlCharacter,
    InvalidQuotedString,
    CarriageReturnError,
    ReverseSolidusError
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
        buffer: [max_buffer_size]u8 = undefined,

        /// The current number of bytes read into the buffer
        buffer_size: usize = 0,

        /// Where we are in the current buffer
        buffer_cursor: usize = 0,

        /// The starting index (wrt. whatever is being read) of the current token
        /// -- we use this instead of the buffer cursor because the buffer cursor can reset
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
            try self.fillBuffer();
            if (self.buffer_size == 0) return self.eofToken();

            try self.skipWhileBytes("\t ");
            self.token = Token{
                .offset = self.token_start,
                .line = self.current_line,
            };

            const byte = self.consume() orelse return self.eofToken();

            const delim_byte = std.meta.intToEnum(Delimiter, byte) catch Delimiter.None;
            switch (delim_byte) {
                // delimiters with special handling
                Delimiter.LineFeed => {
                    self.token.token_type = TokenType.Newline;
                    self.current_line += 1;
                },
                Delimiter.CarriageReturn => {
                    if ((self.peek() orelse 0) == '\n') {
                        _ = self.consume();
                        self.token.token_type = TokenType.Newline;
                        self.current_line += 1;
                    } else {
                        return TokenizerError.CarriageReturnError;
                    }
                },
                Delimiter.Quote => try self.quotedString(),
                Delimiter.ReverseSolidus => return TokenizerError.ReverseSolidusError,

                // the byte is not at delimiter, so handle it accordingly
                Delimiter.None => {
                    switch (byte) {
                        // invalid control characters (white space is already a handled delimiter)
                        0x00...0x1F => return TokenizerError.InvalidControlCharacter,

                        // check if we're starting a comment - otherwise it's a bare string
                        '/' => {
                            if ((self.peek() orelse 0) == '/') {
                                try self.comment();
                            } else {
                                try self.bareString();
                            }
                        },

                        // numbers
                        '0' => {
                            try self.endOfNumberElseBareString();
                        },
                        '1'...'9' => {
                            try self.consumeWhileInRange('0', '9');
                            try self.endOfNumberElseBareString();
                        },

                        else => try self.bareString(),
                    }
                },

                else => {
                    if (delim_byte == Delimiter.Dot and (self.peek() orelse 0) == '.') {
                        _ = self.consume();
                        self.token.token_type = TokenType.Range;
                    } else {
                        self.token.token_type = std.meta.intToEnum(TokenType, byte) catch unreachable;
                    }
                },
            }

            return self.token;
        }

        // ---- Multi-Character Token Parsing

        /// Parses a Comment token.
        fn comment(self: *Self) !void {
            self.token.token_type = TokenType.Comment;
            _ = try self.consumeToBytes("\r\n"); // EOF is fine
        }

        /// Parses a String token.
        fn bareString(self: *Self) !void {
            self.token.token_type = TokenType.String;
            _ = try self.consumeToBytes(delimiters); // EOF is fine
        }

        /// Parses a quoted String token.
        fn quotedString(self: *Self) !void {
            while (try self.consumeToBytes("\\\"")) {
                switch (self.peek().?) {
                    '\\' => {
                        // consume the escape byte and the byte it's escaping
                        _ = self.consume();
                        _ = self.consume();
                        // TODO: There are really only a handful of valid bytes to escape. Consider replacing the second
                        // consume() with something similar to the following:
                        // if (try self.consumeToBytes("bfnrtu\\\"")) _ = self.consume() else return error.InvalidEscapedCharacter;
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
            return TokenizerError.InvalidQuotedString;
        }

        /// Parses a number if the buffer cursor points to a delimiter that would end a number,
        /// otherwise parses a bare string.
        fn endOfNumberElseBareString(self: *Self) !void {
            const byte = self.peek() orelse 0;
            // check for delimiters
            for (delimiters) |d| {
                if (byte == d) {
                    self.token.token_type = TokenType.Number;
                    return;
                }
            }
            try self.bareString();
        }

        // ---- Basic Token Generators

        fn eofToken(self: *Self) Token {
            self.token.offset = self.token_start;
            self.token.size = 0;
            self.token.token_type = TokenType.Eof;
            return self.token;
        }

        // ---- Scanning Operations

        /// Consumes the current buffer byte (pointed to by the buffer cursor), which (in essence)
        /// adds it to the current token. If the buffer is depleted then this returns `null`
        /// otherwise it returns the consumed byte.
        fn consume(self: *Self) ?u8 {
            if (self.advance()) |byte| {
                self.token.size += 1;
                return byte;
            }
            return null;
        }

        /// Advances the current buffer byte (pointed to by the buffer cursor). If the buffer is
        /// depleted then this returns `null` otherwise it returns the byte previously pointed to by
        /// the buffer cursor.
        fn advance(self: *Self) ?u8 {
            if (self.bufferDepleted()) {
                return null;
            }

            // increment the starting position as well since the buffer cursor can reset if it needs to be refilled
            self.token_start += 1;

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
        fn consumeToBytes(self: *Self, targets: []const u8) !bool {
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
                            _ = self.advance();
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
        fn consumeWhileInRange(self: *Self, lo: u8, hi: u8) !void {
            while (self.buffer_size > 0) {
                peekloop: while (self.peek()) |byte| {
                    if (byte >= lo and byte <= hi) {
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

        // ---- Buffer Operations

        /// Checks to see if the buffer cursor is at the end of the buffer.
        fn bufferDepleted(self: Self) callconv(.Inline) bool {
            return self.buffer_cursor == self.buffer_size;
        }

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
        std.mem.copy(u8, dest, self.str[self.cursor .. self.cursor + size]);
        self.cursor += size;
        return size;
    }

    fn reader(self: *Self) Reader {
        return .{ .context = self };
    }
};

/// A structure describing the expected token.
const ExpectedToken = struct {
    str: []const u8,
    line: usize,
    token_type: TokenType,
    // TODO: figure out a way to allow this to fail (like a pass/fail flag)
};

fn expectToken(expected_token: ExpectedToken, token: Token, orig_str: []const u8) !void {
    var ok = true;
    testing.expectEqual(expected_token.line, token.line) catch { ok = false; };
    testing.expectEqual(expected_token.token_type, token.token_type) catch { ok = false; };
    if (token.token_type == TokenType.Eof) {
        testing.expectEqual(orig_str.len, token.offset) catch { ok = false; };
        testing.expectEqual(@as(usize, 0), token.size) catch { ok = false; };

        // also make sure our test token is correct just to make sure
        testing.expectEqualSlices(u8, "", expected_token.str) catch { ok = false; };
    }
    const actual = orig_str[token.offset .. token.offset + token.size];
    testing.expectEqualStrings(expected_token.str, actual) catch { ok = false; };

    if (!ok) {
        return error.TokenTestFailure;
    }
}

fn doTokenTest(str: []const u8, expected_tokens: []const ExpectedToken) !void {
    var string_reader = StringReader.init(str);
    var tokenizer = makeTokenizer(string_reader);
    for (expected_tokens) |token, i| {
        const actual = try tokenizer.next();
        errdefer {
            std.debug.print(
                \\
                \\Expected (#{}):
                \\  ExpectedToken{{ .str = "{s}", .line = {}, .token_type = {} }}
                \\Actual:
                \\  {}
                \\
                \\
            , .{i, token.str, token.line, token.token_type, actual});
        }
        try expectToken(token, actual, str);
    }
}

test "simple comment" {
    const str = "// this is a comment";
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = str, .line = 1, .token_type = TokenType.Comment },
        ExpectedToken{ .str = "", .line = 1, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &expected_tokens);
}

test "comment at end of line" {
    const str =
        \\name = Zooce // this is a comment
        \\one = 12345// this is a comment too
    ;
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "name", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 1, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "Zooce", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "// this is a comment", .line = 1, .token_type = TokenType.Comment },
        ExpectedToken{ .str = "\n", .line = 1, .token_type = TokenType.Newline },
        ExpectedToken{ .str = "one", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 2, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "12345", .line = 2, .token_type = TokenType.Number },
        ExpectedToken{ .str = "// this is a comment too", .line = 2, .token_type = TokenType.Number },
    };
    try doTokenTest(str, &expected_tokens);
}

// TODO: test complex comment - i.e. make sure no special Unicode characters mess this up

test "bare strings" {
    // IMPORTANT - this string is only for testing - it is not a valid zombie-file string
    const str = "I am.a,bunch{of\nstrings 01abc 123xyz";
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "I", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "am", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = ".", .line = 1, .token_type = TokenType.Dot },
        ExpectedToken{ .str = "a", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = ",", .line = 1, .token_type = TokenType.Comma },
        ExpectedToken{ .str = "bunch", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "{", .line = 1, .token_type = TokenType.OpenCurly },
        ExpectedToken{ .str = "of", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "\n", .line = 1, .token_type = TokenType.Newline },
        ExpectedToken{ .str = "strings", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "01abc", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "123xyz", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "", .line = 2, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &expected_tokens);
}

test "quoted string" {
    const str = "\"this is a \\\"quoted\\\" string\\u1234 \t\r\n$(){}[].,=\"";
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = str, .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "", .line = 1, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &expected_tokens);
}

test "zeros" {
    // IMPORTANT - this string is only for testing - it is not a valid zombie-file string
    const str = "0 0\t0.0,0\r\n0\n";
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "0", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = "0", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = "0", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = ".", .line = 1, .token_type = TokenType.Dot },
        ExpectedToken{ .str = "0", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = ",", .line = 1, .token_type = TokenType.Comma },
        ExpectedToken{ .str = "0", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = "\r\n", .line = 1, .token_type = TokenType.Newline },
        ExpectedToken{ .str = "0", .line = 2, .token_type = TokenType.Number },
        ExpectedToken{ .str = "\n", .line = 2, .token_type = TokenType.Newline },
    };
    try doTokenTest(str, &expected_tokens);
}

test "numbers" {
    // IMPORTANT - this string is only for testing - it is not a valid zombie-file string
    const str = "123 1 0123 932 42d";
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "123", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = "1", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = "0123", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "932", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = "42d", .line = 1, .token_type = TokenType.String },
    };
    try doTokenTest(str, &expected_tokens);
}

// TODO: the following tests aren't really testing macros - move these to the parsing file

test "simple macro declaration" {
    const str =
        \\$name = "Zooce Dark"
    ;
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "$", .line = 1, .token_type = TokenType.Dollar },
        ExpectedToken{ .str = "name", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 1, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "\"Zooce Dark\"", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "", .line = 1, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &expected_tokens);
}

test "macro object declaration" {
    const str =
        \\$black_forground = {
        \\    foreground = #2b2b2b
        \\}
    ;
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "$", .line = 1, .token_type = TokenType.Dollar },
        ExpectedToken{ .str = "black_forground", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 1, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "{", .line = 1, .token_type = TokenType.OpenCurly },
        ExpectedToken{ .str = "\n", .line = 1, .token_type = TokenType.Newline },
        ExpectedToken{ .str = "foreground", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 2, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "#2b2b2b", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "\n", .line = 2, .token_type = TokenType.Newline },
        ExpectedToken{ .str = "}", .line = 3, .token_type = TokenType.CloseCurly },
        ExpectedToken{ .str = "", .line = 3, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &expected_tokens);
}

// ref: https://zigforum.org/t/how-to-debug-zig-tests-with-gdb-or-other-debugger/487/4?u=zooce
// zig test ./test.zig --test-cmd gdb --test-cmd '--eval-command=run' --test-cmd-bin
// zig test src/token.zig --test-cmd lldb --test-cmd-bin
// zig test --test-filter "macro array declaration" src/token.zig --test-cmd lldb --test-cmd-bin
test "macro array declaration" {
    const str =
        \\$ports = [ 8000, 8001, 8002 ]
    ;
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "$", .line = 1, .token_type = TokenType.Dollar },
        ExpectedToken{ .str = "ports", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 1, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "[", .line = 1, .token_type = TokenType.OpenSquare },
        ExpectedToken{ .str = "8000", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = ",", .line = 1, .token_type = TokenType.Comma },
        ExpectedToken{ .str = "8001", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = ",", .line = 1, .token_type = TokenType.Comma },
        ExpectedToken{ .str = "8002", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = "]", .line = 1, .token_type = TokenType.CloseSquare },
        ExpectedToken{ .str = "", .line = 1, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &expected_tokens);
}

test "macro with parameters declaration" {
    const str =
        \\$scope_def(scope, settings) = {
        \\    scope = $scope,
        \\\t settings = $settings
        \\}
    ;
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "$", .line = 1, .token_type = TokenType.Dollar },
        ExpectedToken{ .str = "scope_def", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "(", .line = 1, .token_type = TokenType.OpenParen },
        ExpectedToken{ .str = "scope", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = ",", .line = 1, .token_type = TokenType.Comma },
        ExpectedToken{ .str = "settings", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = ")", .line = 2, .token_type = TokenType.CloseParen },
        ExpectedToken{ .str = "=", .line = 2, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "{", .line = 2, .token_type = TokenType.OpenCurly },
        ExpectedToken{ .str = "\n", .line = 2, .token_type = TokenType.Newline },
        ExpectedToken{ .str = "scope", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 3, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "$", .line = 3, .token_type = TokenType.Dollar },
        ExpectedToken{ .str = "scope", .line = 3, .token_type = TokenType.String },
        ExpectedToken{ .str = ",", .line = 3, .token_type = TokenType.Comma },
        ExpectedToken{ .str = "\n", .line = 3, .token_type = TokenType.Newline },
        ExpectedToken{ .str = "settings", .line = 4, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 4, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "$", .line = 4, .token_type = TokenType.Dollar },
        ExpectedToken{ .str = "settings", .line = 4, .token_type = TokenType.String },
        ExpectedToken{ .str = "\n", .line = 4, .token_type = TokenType.Newline },
        ExpectedToken{ .str = "}", .line = 5, .token_type = TokenType.CloseCurly },
        ExpectedToken{ .str = "", .line = 5, .token_type = TokenType.Eof },
    };
}
