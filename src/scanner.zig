const std = @import("std");
const File = std.fs.File;

/// Tokenizes...nuf sed
pub const Tokenizer = struct {
    // ---- Fields

    /// The reader to use for tokenizing
    reader: File.Reader,

    /// The buffer which the reader will read to
    buffer: [100]u8 = undefined,

    /// The current number of bytes read into the buffer
    buffer_size: usize = 0,

    /// The starting index of the current token
    token_start: u32 = 0,

    /// The line where the current token lives (we start at the first line)
    current_line: u32 = 1,

    /// The scanner index (i.e. where we are in the current buffer)
    scanner_index: u32 = 0,

    // ---- Public Interface

    /// Get the next token from the given reader
    pub fn nextToken(self: *Tokenizer) !Token {
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
                    const p = self.peek();
                    if (p != null and p.? == '/') {
                        break :tokenblk try self.comment();
                    } else {
                        break :tokenblk try self.string();
                    }
                },
                '"' => break :tokenblk try self.string(),


                else => break :tokenblk Token{ .line = self.current_line, .token_type = TokenType.ERROR },
            }
        };
        self.token_start += token.size;
        return token;
    }

    // ---- Multi-Character Token Parsing

    /// Parses a COMMENT token, which is two forward slashes followed by any number of any charcter
    /// and ends when a NEWLINE is encountered.
    fn comment(self: *Tokenizer) !Token {
        var size: u32 = try self.skipToByte('\n');
        return Token{ .offset = self.token_start, .size = size, .line = self.current_line, .token_type = TokenType.COMMENT };
    }

    /// Parses an string token.
    fn string(self: *Tokenizer) !Token {
        var size: u32 = 0;
        while(true) {
            size += try self.skipToByte('"');
            if (self.peekPrev().? != '\\') {
                break;
            }
            // consume the escaped double-quote and keep going
            _ = self.consume();
        }

        return Token{ .line = self.current_line, .token_type = TokenType.ERROR };
    }

    // ---- Scanning Operations

    /// Advances the scanner index to the next byte, consuming (and returning) the previous byte.
    /// If the scanner index equals the buffer size, then this returns `null`.
    fn consume(self: *Tokenizer) ?u8 {
        if (self.scanner_index == self.buffer_size) {
            return null;
        }
        self.scanner_index += 1;
        return self.buffer[self.scanner_index - 1];
    }

    /// Returns the byte at the scanner index, or `null` if the scanner index equals the buffer
    /// size.
    fn peek(self: Tokenizer) ?u8 {
        if (self.scanner_index == self.buffer_size) {
            return null;
        }
        return self.buffer[self.scanner_index];
    }

    /// Returns the byte at the previous scanner index, or `null` if either the scanner index is 0
    /// or the buffer size is 0.
    fn peekPrev(self: Tokenizer) ?u8 {
        if (self.scanner_index == 0 or self.buffer_size == 0) {
            return null;
        }
        return self.buffer[self.scanner_index - 1];
    }

    /// Advance the scanner index until the target byte is found, and return the number of bytes
    /// skipped. All bytes leading to the target byte will be consumed, but the target byte will
    /// not be consumed.
    fn skipToByte(self: *Tokenizer, target: u8) !u32 {
        var skipped: u32 = undefined;
        outer: while (self.buffer_size > 0) {
            while (self.peek()) |byte| {
                if (byte == target) {
                    skipped += self.scanner_index;
                    break :outer;
                }
                _ = self.consume();
            }

            // If we're here, then we've scanned to the end of the buffer without finding the byte, so we need to read
            // more bytes into the buffer and keep going. Since we use the scanner index to calculate token size, we
            // also need to accumulate its value since refilling the buffer will reset it.
            skipped += self.scanner_index;
            try self.fillBuffer();
        }
        return skipped;
    }

    // ---- Buffer Operations

    /// Fill the buffer with some bytes from the reader.
    fn fillBuffer(self: *Tokenizer) !void {
        self.buffer_size = try self.reader.read(&self.buffer);
    }
};

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
