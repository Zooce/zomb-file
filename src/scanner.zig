const std = @import("std");
const File = std.fs.File;

pub fn makeTokenizer() Tokenizer {
    return Tokenizer{ .scanner = Scanner{} };
}

/// Tokenizes...nuf sed
pub const Tokenizer = struct {
    /// The starting index of the current token
    start: u32 = 0,

    /// The line where the current token lives (we start at the first line)
    line: u32 = 1,

    scanner: Scanner,

    /// Get the next token from the given reader
    pub fn nextToken(self: *Tokenizer, reader: anytype) !Token {
        var buffer: [100]u8 = undefined;
        var token = tokenblk: {
            while (true) {
                // ideally we'll read in enough bytes to find the next token on the first iteration, but you never know
                const bytesRead = try reader.read(&buffer);
                if (bytesRead == 0) {
                    break :tokenblk Token{ .line = self.line, .token_type = TokenType.EOF };
                }
                self.scanner.init(buffer[0..bytesRead]);
                const b = self.scanner.advance().?;
                switch (b) {
                    // single-charachter tokens
                    ',' => break :tokenblk Token{ .offset = self.start, .size = 1, .line = self.line, .token_type = TokenType.COMMA },
                    '$' => break :tokenblk Token{ .offset = self.start, .size = 1, .line = self.line, .token_type = TokenType.DOLLAR },
                    '.' => break :tokenblk Token{ .offset = self.start, .size = 1, .line = self.line, .token_type = TokenType.DOT },
                    '=' => break :tokenblk Token{ .offset = self.start, .size = 1, .line = self.line, .token_type = TokenType.EQUAL },
                    '{' => break :tokenblk Token{ .offset = self.start, .size = 1, .line = self.line, .token_type = TokenType.LEFT_CURLY },
                    '(' => break :tokenblk Token{ .offset = self.start, .size = 1, .line = self.line, .token_type = TokenType.LEFT_PAREN },
                    '[' => break :tokenblk Token{ .offset = self.start, .size = 1, .line = self.line, .token_type = TokenType.LEFT_SQUARE },
                    '}' => break :tokenblk Token{ .offset = self.start, .size = 1, .line = self.line, .token_type = TokenType.RIGHT_CURLY },
                    ')' => break :tokenblk Token{ .offset = self.start, .size = 1, .line = self.line, .token_type = TokenType.RIGHT_PAREN },
                    ']' => break :tokenblk Token{ .offset = self.start, .size = 1, .line = self.line, .token_type = TokenType.RIGHT_SQUARE },

                    // questionable ???
                    '/' => {
                        const peek = self.scanner.peek();
                        if (peek != null and peek.? == '/') {
                            break :tokenblk self.comment();
                        } else {
                            break :tokenblk self.identifier();
                        }
                    },
                    '"' => break :tokenblk self.identifier(),

                    // multi-charactter tokens


                    else => break :tokenblk Token{ .line = self.line, .token_type = TokenType.ERROR },
                }
            }
        };
        self.start += token.size; // TODO: is this correct?
        return token;
    }

    // The following functions are tokenizers for specific, multi-character tokens that take some work to scan.

    fn comment(self: *Tokenizer) Token {
        while (self.scanner.peek()) |p| {
            if (p == '\n') {
                break;
            }
            _ = self.scanner.advance();
        }
        if (self.scanner.peek() == null) {
            // It's possible that we scan to the end of the buffer before finding a newline - in this case, we need to:
            //  - save the size of the current buffer (we'll need to add this to the final token size)
            //  - use the reader to refill the buffer
            //  - reinitialize the scanner with the new buffer
            //  - keep going with this loop until we find a newline
            std.log.err("TODO: we need to get more bytes!", .{});
        }
        return Token{ .offset = self.start, .size = self.scanner.index, .line = self.line, .token_type = TokenType.COMMENT };
    }

    fn identifier(self: *Tokenizer) Token {
        // TODO: implement me
        return Token{ .line = self.line, .token_type = TokenType.ERROR };
    }
};

/// The Scanner is just a wrapper around a slice of bytes we want to scan. Note that it only scans forward.
const Scanner = struct {
    /// The bytes to scan
    bytes: []const u8 = undefined,

    /// The current index in the slice of bytes
    index: u32 = 0,

    /// Initialize the Scanner with a new set of bytes
    fn init(self: *Scanner, bytes: []const u8) void {
        self.bytes = bytes;
        self.index = 0;
    }

    /// Advances the current index to the next byte, consuming (and returning) the byte at the current index.
    /// If the current index equals or exceeds `bytes.len`, then this returns `null`.
    fn advance(self: *Scanner) ?u8 {
        if (self.index == self.bytes.len) {
            return null;
        }
        const b = self.bytes[self.index];
        self.index += 1;
        return b;
    }

    /// Returns the byte at the current index, or `null` if the current index equals or exceeds `bytes.len`.
    fn peek(self: Scanner) ?u8 {
        if (self.index >= self.bytes.len) {
            return null;
        }
        return self.bytes[self.index];
    }
};

/// Token types
pub const TokenType = packed enum(u8) {
    // single character tokens
    COMMA, DOLLAR, DOT, EQUAL,
    LEFT_CURLY, RIGHT_CURLY,
    LEFT_PAREN, RIGHT_PAREN,
    LEFT_SQUARE, RIGHT_SQUARE,

    // literals
    COMMENT, IDENTIFIER, VARIABLE, VALUE,

    // others
    ERROR, EOF,
};

/// Token - We store only the offset and the token size instead of slices becuase
/// we don't want to deal with carrying around slices -- no need to store that kind
/// of memory.
pub const Token = packed struct {
    /// The offset into the file where this token begins (max = 4,294,967,295)
    offset: u32 = 0,

    /// The length of this token (max length = 4,294,967,295)
    size: u32 = 0,

    /// The line in the file where this token was discovered (max = 4,294,967,295)
    line: u32,

    /// The type of this token (duh)
    token_type: TokenType,
};

test "size of token" {
    // This "optimization" test is not necessary. I'm just playing around and learning Zig at this point.

    const expect = @import("std").testing.expect;

    var size: u8 = 1;   // TokenType
    size += 4;          // offset
    size += 4;          // size
    size += 4;          // line

    try expect(@sizeOf(Token) == size);
}
