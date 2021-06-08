const std = @import("std");

const token = @import("token.zig");
pub const Tokenizer = token.Tokenizer;
pub const TokenType = token.TokenType;
pub const Token = token.Token;

pub const Parser = @import("parse.zig").Parser;

pub const StringReader = @import("string_reader.zig").StringReader;

test {
    // the tests from each of these modules will be run when we import them here
    _ = @import("scan.zig");
    _ = @import("token.zig");
    _ = @import("parse.zig");
}
