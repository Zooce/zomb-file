const std = @import("std");
const Scanner = @import("scanner.zig").Scanner;

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
    MultiLineString,
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

/// Tokenizes...nuf sed
pub fn Tokenizer(comptime FileType_: type, buffer_size_: anytype) type {
    return struct {

        const Self = @This();
        const ScannerType = Scanner(FileType_, buffer_size_);

        scanner: ScannerType,

        /// The token currently being discovered
        token: Token = undefined,

        pub fn init(file_: *FileType_) Self {
            return Self{
                .scanner = ScannerType.init(file_),
            };
        }

        pub fn deinit(self: *Self) void {
            self.scanner.deinit();
        }

        /// Get the next token
        pub fn next(self: *Self) !Token {
            try self.skipSeparators();
            self.token = Token{
                .offset = self.scanner.file_cursor,
                .line = self.scanner.current_line,
            };

            const byte = self.scanner.peek() orelse return self.eofToken();

            const delim_byte = std.meta.intToEnum(Delimiter, byte) catch Delimiter.None;
            switch (delim_byte) {
                // delimiters with special handling
                .Quote => try self.quotedString(),
                .ReverseSolidus => try self.multiLineString(),

                // the byte is not at delimiter, so handle it accordingly
                .None => {
                    switch (byte) {
                        // invalid control characters (white space is already a handled delimiter)
                        0x00...0x1F => return error.InvalidControlCharacter,

                        '/' => try self.commentOrBareString(),

                        // numbers
                        '0'...'9' => {
                            try self.numberOrBareString();
                        },

                        else => try self.bareString(),
                    }
                },

                else => try self.delimiter(),
            }

            return self.token;
        }

        // ---- Multi-Character Token Parsing

        /// Parses a Comment token.
        fn comment(self: *Self) !void {
            self.token.token_type = TokenType.Comment;

            if (self.consume().? != '/') return error.InvalidComment;
            if (self.consume().? != '/') return error.InvalidComment;
            _ = self.consumeToBytes("\r\n"); // EOF is fine
        }

        fn delimiter(self: *Self) !void {
            if (self.consume()) |byte| {
                if (byte == '.') {
                    if ((self.scanner.peek() orelse 0) == '.') {
                        _ = self.consume();
                        self.token.token_type = TokenType.Range;
                        return;
                    }
                }
                self.token.token_type = std.meta.intToEnum(TokenType, byte) catch unreachable;
            } else {
                return error.InvalidDelimiter;
            }
        }

        /// Parses a String token.
        fn bareString(self: *Self) !void {
            self.token.token_type = TokenType.String;

            _ = self.consumeToBytes(delimiters); // EOF is fine
        }

        /// Parses a quoted String token.
        fn quotedString(self: *Self) !void {
            self.token.token_type = TokenType.String;

            if (self.consume().? != '\"') return error.InvalidQuotedString;
            while (self.consumeToBytes("\\\"")) {
                switch (self.scanner.peek().?) {
                    '\\' => {
                        try self.consumeEscapeSequence();
                    },
                    '"' => {
                        // consume the ending double-quote and return
                        _ = self.consume();
                        return;
                    },
                    else => unreachable,
                }
            }
            // if we're here, that's an error
            return error.InvalidQuotedString;
        }

        /// Parses a multi-line string, based on the following rule:
        /// - The `\\` delimiter starts each line of a multi-line string.
        /// - Multi-line strings run to the end of the line they start on.
        /// - The ending newline (either `\r\n` or `\n`) should be included in the token's length.
        /// - More than one newline between multi-line strings starts a new multi-line string.
        fn multiLineString(self: *Self) !void {
            self.token.token_type = TokenType.MultiLineString;

            var end_is_crlf = false;
            while (true) {
                if (self.consume().? != '\\') return error.InvalidFirstMultiLineStringByte;
                if (self.consume().? != '\\') return error.InvalidSecondMultiLineStringByte;
                if (!self.consumeToBytes("\r\n")) return; // EOF is fine
                // newlines are part of multi-line strings to consume them so they are counted towards the token length
                if (self.consume()) |byte| {
                    switch (byte) {
                        '\r' => {
                            if (self.consume().? != '\n') return error.CarriageReturnError;
                            end_is_crlf = true;
                        },
                        '\n' => end_is_crlf = false,
                        else => unreachable,
                    }
                }
                self.consumeWhileBytes("\t ");
                if ((self.scanner.peek() orelse 0) != '\\') {
                    break;
                }
            }

            // the last newline is not part of the token
            if (end_is_crlf) self.token.size -= 2 else self.token.size -= 1;
        }

        fn commentOrBareString(self: *Self) !void {
            if (self.scanner.peek().? != '/') return error.InvalidCommentOrBareString;
            if ((self.scanner.peekNext() orelse 0) == '/') {
                try self.comment();
            } else {
                try self.bareString();
            }
        }

        fn numberOrBareString(self: *Self) !void {
            self.token.token_type = TokenType.Number;

            switch (self.consume().?) {
                '0' => {
                    if (self.atDelimiterOrEof()) {
                        return;
                    }
                },
                '1'...'9' => {
                    self.consumeWhileInRange('0', '9');
                    if (self.atDelimiterOrEof()) {
                        return;
                    }
                },
                else => return error.InvalidNumberOrBareString,
            }
            try self.bareString();
        }

        // ---- Basic Token Generators

        fn eofToken(self: *Self) Token {
            self.token.offset = self.scanner.file_cursor;
            self.token.size = 0;
            self.token.token_type = TokenType.Eof;
            return self.token;
        }

        // ---- Scanning Operations

        /// Consumes the current buffer byte (pointed to by the buffer cursor), which (in essence)
        /// adds it to the current token. If the buffer is depleted then this returns `null`
        /// otherwise it returns the consumed byte.
        fn consume(self: *Self) ?u8 {
            if (self.scanner.advance()) |byte| {
                self.token.size += 1;
                return byte;
            }
            return null;
        }

        /// Move the buffer cursor forward until one of the target bytes is found. All bytes leading
        /// to the discovered target byte will be consumed, but that target byte will not be
        /// consumed. If we can't find any of the target bytes, we return `false` otherwise we
        /// return `true`.
        fn consumeToBytes(self: *Self, targets_: []const u8) bool {
            while (self.scanner.peek()) |byte| {
                for (targets_) |target| {
                    if (byte == target) {
                        return true;
                    }
                }
                _ = self.consume();
            }

            // We didn't find any of the target bytes.
            return false;
        }

        fn consumeWhileBytes(self: *Self, targets_: []const u8) void {
            peekloop: while (self.scanner.peek()) |byte| {
                for (targets_) |target| {
                    if (byte == target) {
                        _ = self.consume();
                        continue :peekloop;
                    }
                }
                // The byte we're looking at did not match any target, so return.
                return;
            }
        }

        /// Move the buffer cursor forward while it points to any byte in the specified, inclusive
        /// range. All bytes scanned are consumed, while the final byte (which is not within the
        /// specified range) is not.
        fn consumeWhileInRange(self: *Self, lo_: u8, hi_: u8) void {
            peekloop: while (self.scanner.peek()) |byte| {
                if (byte >= lo_ and byte <= hi_) {
                    _ = self.consume();
                    continue :peekloop;
                }
                // The current byte is not in the specified range, so we stop here.
                return;
            }
        }

        fn consumeEscapeSequence(self: *Self) !void {
            if (self.consume().? != '\\') return error.InvalidEscapeSequence;
            if (self.consume()) |byte| {
                switch (byte) {
                    '\"', '\\', 'b', 'f', 'n', 'r', 't' => return,
                    'u' => {
                        try self.consumeHex();
                        try self.consumeHex();
                        try self.consumeHex();
                        try self.consumeHex();
                        return;
                    },
                    else => return error.InvalidEscapeSequence,
                }
            }
            return error.InvalidEscapeSequence;
        }

        fn consumeHex(self: *Self) !void {
            if (self.consume()) |byte| {
                switch (byte) {
                    '0'...'9', 'A'...'F', 'a'...'f' => return,
                    else => return error.InvalidHex,
                }
            }
            return error.InvalidHex;
        }

        /// Move the buffer cursor forward while one of the target bytes is found.
        fn skipWhileBytes(self: *Self, targets_: []const u8) void {
            peekloop: while (self.scanner.peek()) |byte| {
                for (targets_) |target| {
                    if (byte == target) {
                        _ = self.scanner.advance();
                        continue :peekloop;
                    }
                }
                // The byte we're looking at did not match any target, so return.
                return;
            }
        }

        /// Advance the scanner until the start of a token is found. If more than one comma is
        /// encountered while skipping separators, error.TooManyCommas error is returned.
        fn skipSeparators(self: *Self) !void {
            var found_comma = false;
            while (self.scanner.peek()) |byte| {
                switch (byte) {
                    ' ', '\t', '\n' => {
                        _ = self.scanner.advance();
                    },
                    '\r' => { // TODO: is this block necessary?
                        _ = self.scanner.advance();
                        if ((self.scanner.peek() orelse 0) == '\n') {
                            _ = self.scanner.advance();
                        } else {
                            return error.CarriageReturnError;
                        }
                    },
                    ',' => {
                        if (found_comma) {
                            return error.TooManyCommas;
                        }
                        found_comma = true;
                        _ = self.scanner.advance();
                    },
                    else => return,
                }
            }
        }

        fn atDelimiterOrEof(self: *Self) bool {
            const byte = self.scanner.peek() orelse return true; // EOF is fine
            // check for delimiters
            for (delimiters) |d| {
                if (byte == d) {
                    return true;
                }
            }
            return false;
        }
    }; // end Tokenizer struct
} // end Tokenizer type fn


//==============================================================================
//
//
//
// Testing
//==============================================================================

const testing = std.testing;
const StringReader = @import("testing/string_reader.zig").StringReader;

const test_buffer_size: usize = 32;
const StringTokenizer = Tokenizer(StringReader, test_buffer_size);

/// A structure describing the expected token.
const ExpectedToken = struct {
    str: []const u8,
    line: usize,
    token_type: TokenType,
    // TODO: figure out a way to allow this to fail (like a pass/fail flag)
};

fn expectToken(expected_token_: ExpectedToken, token_: Token, orig_str_: []const u8) !void {
    var ok = true;
    testing.expectEqual(expected_token_.line, token_.line) catch { ok = false; };
    testing.expectEqual(expected_token_.token_type, token_.token_type) catch { ok = false; };
    if (token_.token_type == TokenType.Eof) {
        testing.expectEqual(orig_str_.len, token_.offset) catch { ok = false; };
        testing.expectEqual(@as(usize, 0), token_.size) catch { ok = false; };

        // also make sure our test token is correct just to make sure
        testing.expectEqualSlices(u8, "", expected_token_.str) catch { ok = false; };
    }
    const actual = orig_str_[token_.offset .. token_.offset + token_.size];
    testing.expectEqualStrings(expected_token_.str, actual) catch { ok = false; };

    if (!ok) {
        return error.TokenTestFailure;
    }
}

fn doTokenTest(str_: []const u8, expected_tokens_: []const ExpectedToken) !void {
    var string_reader = StringReader{ .str = str_ };
    var tokenizer = StringTokenizer.init(&string_reader);
    defer tokenizer.deinit();
    for (expected_tokens_) |token, i| {
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
        try expectToken(token, actual, str_);
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
        \\one = 12345// this is not a comment
    ;
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "name", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 1, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "Zooce", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "// this is a comment", .line = 1, .token_type = TokenType.Comment },
        ExpectedToken{ .str = "one", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 2, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "12345//", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "this", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "is", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "not", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "a", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "comment", .line = 2, .token_type = TokenType.String },
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
        ExpectedToken{ .str = "bunch", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "{", .line = 1, .token_type = TokenType.OpenCurly },
        ExpectedToken{ .str = "of", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "strings", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "01abc", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "123xyz", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "", .line = 2, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &expected_tokens);
}

test "quoted string" {
    const str = "\"this is a \\\"quoted\\\" string\\u1234 \\t\\r\\n$(){}[].,=\"";
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
        ExpectedToken{ .str = "0", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = "0", .line = 2, .token_type = TokenType.Number },
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
        ExpectedToken{ .str = "foreground", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 2, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "#2b2b2b", .line = 2, .token_type = TokenType.String },
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
        \\$ports = [ 8000 8001 8002 ]
    ;
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "$", .line = 1, .token_type = TokenType.Dollar },
        ExpectedToken{ .str = "ports", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 1, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "[", .line = 1, .token_type = TokenType.OpenSquare },
        ExpectedToken{ .str = "8000", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = "8001", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = "8002", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = "]", .line = 1, .token_type = TokenType.CloseSquare },
        ExpectedToken{ .str = "", .line = 1, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &expected_tokens);
}

test "macro with parameters declaration" {
    const str =
        \\$scope_def (scope settings) = {
        \\    scope = $scope
        \\    settings = $settings
        \\}
    ;
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "$", .line = 1, .token_type = TokenType.Dollar },
        ExpectedToken{ .str = "scope_def", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "(", .line = 1, .token_type = TokenType.OpenParen },
        ExpectedToken{ .str = "scope", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "settings", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = ")", .line = 1, .token_type = TokenType.CloseParen },
        ExpectedToken{ .str = "=", .line = 1, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "{", .line = 1, .token_type = TokenType.OpenCurly },
        ExpectedToken{ .str = "scope", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 2, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "$", .line = 2, .token_type = TokenType.Dollar },
        ExpectedToken{ .str = "scope", .line = 2, .token_type = TokenType.String },
        ExpectedToken{ .str = "settings", .line = 3, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 3, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "$", .line = 3, .token_type = TokenType.Dollar },
        ExpectedToken{ .str = "settings", .line = 3, .token_type = TokenType.String },
        ExpectedToken{ .str = "}", .line = 4, .token_type = TokenType.CloseCurly },
        ExpectedToken{ .str = "", .line = 4, .token_type = TokenType.Eof },
    };
    try doTokenTest(str, &expected_tokens);
}

test "string-string kv-pair" {
    const str = "key = value";
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "key", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 1, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "value", .line = 1, .token_type = TokenType.String },
    };
    try doTokenTest(str, &expected_tokens);
}

test "number-number kv-pair" {
    const str = "123 = 456";
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "123", .line = 1, .token_type = TokenType.Number },
        ExpectedToken{ .str = "=", .line = 1, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "456", .line = 1, .token_type = TokenType.Number },
    };
    try doTokenTest(str, &expected_tokens);
}

test "string-multi-line-string kv-pair" {
    const str =
        \\key = \\first line
        \\      \\ second line
        \\     \\   third line
        \\123 = 456
    ;
    const expected_tokens = [_]ExpectedToken{
        ExpectedToken{ .str = "key", .line = 1, .token_type = TokenType.String },
        ExpectedToken{ .str = "=", .line = 1, .token_type = TokenType.Equals },
        ExpectedToken{ .str = \\\\first line
                              \\      \\ second line
                              \\     \\   third line
                       , .line = 1, .token_type = TokenType.MultiLineString },
        ExpectedToken{ .str = "123", .line = 4, .token_type = TokenType.Number },
        ExpectedToken{ .str = "=", .line = 4, .token_type = TokenType.Equals },
        ExpectedToken{ .str = "456", .line = 4, .token_type = TokenType.Number },
    };
    try doTokenTest(str, &expected_tokens);
}
