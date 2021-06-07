const std = @import("std");

const Tokenizer = @import("token.zig").Tokenizer;
const TokenType = @import("token.zig").TokenType;
const Token = @import("token.zig").Token;

const State = enum {
    Decl,
    MacroDecl,
    KvPair,
    Object,
    Array,
    MacroUse,
    MacroUseParams,
};

pub fn Parser(comptime FileType_: type, buffer_size_: anytype) type {
    return struct {
        const Self = @This();
        const ParserTokenizer = Tokenizer(FileType_, buffer_size_);
        const max_expected_count = 5;

        tokenizer: ParserTokenizer,

        expected_tokens: [max_expected_count]?TokenType = .{ null } ** max_expected_count,

        state: State = State.Decl,

        // Each state has a set of stages in which they have different expectations of the next token.
        state_stage: u8 = 0,

        // NOTE: the following bit-stack setup is based on zig/lib/std/json.zig
        stack: u128 = 0,
        stack_size: u8 = 0,

        const stack_shift = 2; // 2 bits per stack element
        const max_stack_size = 64; // this is fairly reasonable (add more stacks if we need more?)

        // stack elements
        const stack_object = 0;
        const stack_array = 1;
        const stack_macro_use = 2;
        const stack_macro_use_params = 3;


        pub fn init(file_: *FileType_) Self {
            return Self{
                .tokenizer = ParserTokenizer.init(file_),
            };
        }

        pub fn deinit(self: *Self) void {
            self.tokenizer.deinit();
        }

        pub fn parse(self: *Self) !void {
            var token = try self.tokenizer.next();

            // ===--- for prototyping only ---===
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            var token_string = std.ArrayList(u8).init(&gpa.allocator);
            defer token_string.deinit();
            // ===----------------------------===

            parseloop: while (token.token_type != TokenType.Eof) {
                // ===--- for prototyping only ---===
                _ = try self.tokenizer.tokenString(token, &token_string);
                std.log.err(
                    \\
                    \\State: {} (stage = {})
                    \\Stack: 0x{b:0>128} (size = {})
                    \\Type : {} (line = {})
                    \\Token: {s}
                    \\
                    , .{
                        self.state,
                        self.state_stage,
                        self.stack,
                        self.stack_size,
                        token.token_type,
                        token.line,
                        token_string.items,
                    }
                );
                token_string.clearRetainingCapacity();
                // ===----------------------------===

                switch (self.state) {

                    // stage   expected tokens  >> next stage/state
                    // --------------------------------------------
                    //     -   Dollar           >> MacroDecl
                    //         String or Number >> KvPair
                    //         else             >> error
                    .Decl => switch (token.token_type) {
                        .Dollar => self.state = State.MacroDecl,
                        .String, .Number => self.state = State.KvPair,
                        else => return error.UnexpectedDeclToken,
                    },

                    // stage   expected tokens  >> next stage/state
                    // --------------------------------------------
                    //     0   String or Number >> 1
                    //         else             >> error
                    // --------------------------------------------
                    //     1   OpenParen        >> 2
                    //         Equals           >> 4
                    //         else             >> error
                    // --------------------------------------------
                    //     2   String or Number >> -
                    //         CloseParen       >> 3
                    //         else             >> error
                    // --------------------------------------------
                    //     3   Equals           >> 4
                    //         else             >> error
                    // --------------------------------------------
                    //     4   String or Number >> Decl
                    //         MultiLineString  >> Decl
                    //         Dollar           >> MacroUse
                    //         OpenCurly        >> Object
                    //         OpenSquare       >> Array
                    //         else             >> error
                    .MacroDecl => switch (self.state_stage) {
                        0 => switch (token.token_type) { // macro key
                            .String, .Number => self.state_stage = 1,
                            else => return error.UnexpectedMacroDeclStage0Token,
                        },
                        1 => switch (token.token_type) { // parameters or equals
                            .OpenParen => self.state_stage = 2,
                            .Equals => self.state_stage = 4,
                            else => return error.UnexpectedMacroDeclStage1Token,
                        },
                        2 => switch (token.token_type) { // parameters
                            .String, .Number => {},
                            .CloseParen => self.state_stage = 3,
                            else => return error.UnexpectedMacroDeclStage2Token,
                        },
                        3 => switch (token.token_type) { // equals
                            .Equals => self.state_stage = 4,
                            else => return error.UnexpectedMacroDeclStage3Token,
                        },
                        4 => switch (token.token_type) { // value
                            .String, .Number, .MultiLineString => {
                                self.state = State.Decl;
                                self.state_stage = 0;
                            },
                            .Dollar => try self.stackPush(stack_macro_use),
                            .OpenCurly => try self.stackPush(stack_object),
                            .OpenSquare => try self.stackPush(stack_array),
                            else => return error.UnexpectedMacroDeclStage4Token,
                        },
                        else => return error.UnexpectedMacroDeclStage,
                    },

                    // stage   expected tokens  >> next stage/state
                    // --------------------------------------------------
                    //     0   Equals           >> 1
                    //         else             >> error
                    // --------------------------------------------------
                    //     1   String or Number >> Object (stack) or Decl
                    //         MultiLineString  >> Object (stack) or Decl
                    //         Dollar           >> MacroUse
                    //         OpenCurly        >> Object
                    //         OpenSquare       >> Array
                    //         else             >> error
                    .KvPair => switch (self.state_stage) {
                        0 => switch (token.token_type) {
                            .Equals => self.state_stage = 1,
                            else => return error.UnexpectedKvPairStage0Token,
                        },
                        1 => switch (token.token_type) {
                            .String, .Number, .MultiLineString => {
                                self.state_stage = 0;
                                if (self.stackPeek()) |stack_type| {
                                    switch (stack_type) {
                                        stack_object => self.state = State.Object,
                                        else => return error.UnexpectedKvPairStackPeek,
                                    }
                                } else {
                                    self.state = State.Decl;
                                }
                            },
                            .Dollar => try self.stackPush(stack_macro_use),
                            .OpenCurly => try self.stackPush(stack_object),
                            .OpenSquare => try self.stackPush(stack_array),
                            else => return error.UnexpectedKvPairStage1Token,
                        },
                        else => return error.UnexpectedKvPairStage,
                    },

                    // stage   expected tokens  >> next stage/state
                    // --------------------------------------------
                    //     -   String or Number >> KvPair
                    //         CloseCurly       >> stack or Decl
                    //         else             >> error
                    .Object => switch (token.token_type) {
                        .String, .Number => self.state = State.KvPair,
                        .CloseCurly => try self.stackPop(),
                        else => return error.UnexpectedObjectToken,
                    },

                    // stage   expected tokens  >> next stage/state
                    // --------------------------------------------
                    //     -   String or Number >> -
                    //         MultiLineString  >> -
                    //         Dollar           >> MacroUse
                    //         OpenCurly        >> Object
                    //         OpenSquare       >> Array
                    //         CloseSquare      >> stack or Decl
                    //         else             >> error
                    .Array => switch (token.token_type) {
                        .String, .Number, .MultiLineString => {},
                        .Dollar => try self.stackPush(stack_macro_use),
                        .OpenCurly => try self.stackPush(stack_object),
                        .OpenSquare => try self.stackPush(stack_array),
                        .CloseSquare => try self.stackPop(),
                        else => return error.UnexpectedArrayToken,
                    },

                    // stage   expected tokens  >> next stage/state
                    // --------------------------------------------
                    //     0   String or Number >> 1
                    //         else             >> error
                    // --------------------------------------------
                    // pop 1   Dot              >> 0
                    //         OpenSquare       >> 2
                    //         OpenParen        >> MacroUseParams
                    //         else             >> stack or Decl (keep token)
                    // --------------------------------------------
                    //     2   Number           >> 3
                    //         Range            >> 4
                    //         else             >> error
                    // --------------------------------------------
                    //     3   Range            >> 4
                    //         else             >> error
                    // --------------------------------------------
                    //     4   Number           >> 5
                    //         CloseSquare      >> 1
                    //         else             >> error
                    // --------------------------------------------
                    //     5   CloseSquare      >> 1
                    //         else             >> error
                    .MacroUse => switch (self.state_stage) {
                        0 => switch (token.token_type) { // macro key
                            .String, .Number => self.state_stage = 1,
                            else => return error.UnexpectedMacroUseStage0Token,
                        },
                        1 => switch (token.token_type) { // params or accessor
                            .Dot => self.state_stage = 0,
                            .OpenSquare => self.state_stage = 2,
                            .OpenParen => try self.stackPush(stack_macro_use_params),
                            else => {
                                try self.stackPop();
                                continue :parseloop;
                            },
                        },
                        2 => switch (token.token_type) { // range start index or range token
                            .Number => self.state_stage = 3,
                            .Range => self.state_stage = 4,
                            else => return error.UnexpectedMacroUseStage2Token,
                        },
                        3 => switch (token.token_type) { // range token
                            .Range => self.state_stage = 4,
                            else => return error.UnexpectedMacroUseStage3Token,
                        },
                        4 => switch (token.token_type) { // range end index or end of range accessor
                            .Number => self.state_stage = 5,
                            .CloseSquare => self.state_stage = 1,
                            else => return error.UnexpectedMacroUseStage4Token,
                        },
                        5 => switch (token.token_type) { // end of range accessor
                            .CloseSquare => self.state_stage = 1,
                            else => return error.UnexpectedMacroUseStage5Token,
                        },
                        else => return error.UnexpectedMacroUseStage,
                    },

                    // stage   expected tokens  >> next stage/state
                    // --------------------------------------------
                    //     0   String or Number >> 1
                    //         MultiLineString  >> 1
                    //         Dollar           >> MacroUse
                    //         OpenCurly        >> Object
                    //         OpenSquare       >> Array
                    //         else             >> error
                    // --------------------------------------------
                    // pop 1   String or Number >> -
                    //         MultiLineString  >> -
                    //         Dollar           >> MacroUse
                    //         OpenCurly        >> Object
                    //         OpenSquare       >> Array
                    //         CloseParen       >> stack or Decl
                    //         else             >> error
                    .MacroUseParams => switch (self.state_stage) {
                        0 => switch (token.token_type) {
                            .String, .Number, .MultiLineString => self.state_stage = 1,
                            .Dollar => try self.stackPush(stack_macro_use),
                            .OpenCurly => try self.stackPush(stack_object),
                            .OpenSquare => try self.stackPush(stack_array),
                            else => return error.UnexpectedMacroUseParamsStage0Token,
                        },
                        1 => switch (token.token_type) {
                            .String, .Number, .MultiLineString => {},
                            .Dollar => try self.stackPush(stack_macro_use),
                            .OpenCurly => try self.stackPush(stack_object),
                            .OpenSquare => try self.stackPush(stack_array),
                            .CloseParen => try self.stackPop(),
                            else => return error.UnexpectedMacroUseParamsStage1Token,
                        },
                        else => return error.UnexpectedMacroUseParamsStage,
                    },
                }

                token = try self.tokenizer.next();
            }
        }

        fn stackPush(self: *Self, stack_type: u2) !void {
            if (self.stack_size > max_stack_size) {
                return error.TooManyStackPushes;
            }
            self.stack <<= stack_shift;
            self.stack |= stack_type;
            self.stack_size += 1;
            switch (stack_type) {
                stack_object => self.state = State.Object,
                stack_array => self.state = State.Array,
                stack_macro_use => self.state = State.MacroUse,
                stack_macro_use_params => self.state = State.MacroUseParams,
            }
            self.state_stage = 0;
        }

        fn stackPop(self: *Self) !void {
            if (self.stack_size == 0) {
                return error.TooManyStackPops;
            }
            self.stack >>= stack_shift;
            self.stack_size -= 1;
            if (self.stack_size == 0) {
                self.state = State.Decl;
                return;
            }
            switch (self.stack & 0b11) {
                stack_object => {
                    self.state = State.Object;
                    self.state_stage = 0;
                },
                stack_array => {
                    self.state = State.Array;
                    self.state_stage = 0;
                },
                stack_macro_use => {
                    self.state = State.MacroUse;
                    self.state_stage = 1;
                },
                stack_macro_use_params => {
                    self.state = State.MacroUseParams;
                    self.state_stage = 1;
                },
                else => return error.UnexpectedStackElement,
            }
        }

        fn stackPeek(self: Self) ?u2 {
            if (self.stack_size == 0) {
                return null;
            }
            return @intCast(u2, self.stack & 0b11);
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

const StringReader = @import("string_reader.zig").StringReader;
const StringParser = Parser(StringReader, 32);

test "temp parse test" {
    const str =
        \\$m1(one two) = { // macro with paramters
        \\    hello = $one
        \\    goodbye = [ 42 // the answer
        \\        $two ]
        \\}
        \\$hi = this // macro without parameters
        \\// Did you notice you can have comments?
        \\cool = {
        \\    ports = [ 800 900 ]
        \\    this = $hi
        \\    "wh.at" = $m1( 0 $m1( a, b ) ).goodbye  // commas are optional, yay!
        \\    // "thing" points to a multi-line string...cool I guess
        \\    oh_yea = { thing = \\cool = {
        \\                       \\    ports = [ 800 900 ]
        \\                       \\    this = $hi
        \\                       \\    what = $m1( 0 $m1( a b ) ).goodbye
        \\                       \\    oh_yea = { thing = "nope" }
        \\                       \\}
        \\                       \\$m1(one two) = {
        \\                       \\    hello = $one
        \\                       \\    goodbye = $two
        \\                       \\}
        \\    }
        \\}
    ;
    var string_reader = StringReader{ .str = str };
    var parser = StringParser.init(&string_reader);
    defer parser.deinit();
    try parser.parse();
}

test "stack logic" {
    var stack: u128 = 0;
    var stack_size: u8 = 0;
    const max_stack_size: u8 = 64;
    const shift = 2;
    const obj = 0;
    const arr = 1;
    const mac = 2;
    const par = 3;

    try testing.expectEqual(@as(u128, 0x0000_0000_0000_0000_0000_0000_0000_0000), stack);

    // This loop should push 0, 1, 2, and 3 in sequence until the max stack size
    // has been reached.
    var t: u8 = 0;
    while (stack_size < max_stack_size) {
        stack <<= shift;
        stack |= t;
        stack_size += 1;
        t = (t + 1) % 4;
        if (stack_size != max_stack_size) {
            try testing.expect(@as(u128, 0x1B1B_1B1B_1B1B_1B1B_1B1B_1B1B_1B1B_1B1B) != stack);
        }
    }
    try testing.expectEqual(@as(u128, 0x1B1B_1B1B_1B1B_1B1B_1B1B_1B1B_1B1B_1B1B), stack);
    while (stack_size > 0) {
        t = if (t == 0) 3 else (t - 1);
        try testing.expectEqual(@as(u128, t), (stack & 0b11));
        stack >>= shift;
        stack_size -= 1;
    }
    try testing.expectEqual(@as(u128, 0x0000_0000_0000_0000_0000_0000_0000_0000), stack);
}
