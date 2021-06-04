const std = @import("std");

const Tokenizer = @import("token.zig").Tokenizer;
const TokenType = @import("token.zig").TokenType;
const Token = @import("token.zig").Token;

const State = enum {
    /// The top level declaration state.
    ///
    /// Expected tokens:
    ///     (0) - .Dollar >> MacroDecl
    ///         - .String .Number >> KvPair
    ///     else >> Error
    Decl,

    /// The macro-decl state.
    ///
    /// Expected tokens:
    ///     (0) .String .Number >> (1)
    ///     (1) - .Equals >> (4)
    ///         - .OpenParen >> (2)
    ///     (2) - .String .Number > (2)
    ///         - .CloseParen >> (3)
    ///     (3) .Equals >> (4)
    ///     (4) - .String .Number .MultiLineString >> Decl
    ///         - .Dollar >> MacroUse
    ///         - .OpenCurly >> Object
    ///         - .OpenSquare >> Array
    ///     else >> Error
    MacroDecl,

    /// The key-value pair state.
    ///
    /// Expected tokens:
    ///     (0) .Equals >> (1)
    ///     (1) - .String .Number .MultiLineString >> "top of stack" or Decl
    ///         - .Dollar >> MacroUse
    ///         - .OpenCurly >> Object
    ///         - .OpenSquare >> Array
    ///     else >> Error
    KvPair,

    /// The object state.
    ///
    /// This is a nested structure, so when entering this state, it must also be pushed onto the
    /// stack.
    ///
    /// Expected tokens:
    ///     (0) - .String .Number >> KvPair
    ///         - .CloseCurly >> "top of stack" or Decl
    ///     else >> Error
    Object,

    /// The array state.
    ///
    /// This is a nested structure, so when entering this state, it must also be pushed onto the
    /// stack.
    ///
    /// Expected tokens:
    ///     (0) - .String .Number .MultiLineString >> (0)
    ///         - .Dollar >> MacroUse
    ///         - .OpenCurly >> Object
    ///         - .OpenSquare >> Array
    ///         - .CloseSquare >> "top of stack" or Decl
    ///     else >> Error
    Array,

    /// The macro-use state.
    ///
    /// This is a nested structure, so when entering this state, it must also be pushed onto the
    /// stack.
    ///
    /// Expected tokens:
    ///                 (0) .String .Number >> (1)
    /// top of stack -> (1) - .Dot >> (0)
    ///                     - .OpenParen >> MacroUseParams
    ///                     - .OpenSquare >> (2)
    ///                 (2) - .Number >> (3)
    ///                     - .Range >> (4)
    ///                 (3) - .Range >> (4)
    ///                 (4) - .Number >> (5)
    ///                     - .CloseSquare >> (1)
    ///                 (5) - .CloseSquare >> (1)
    ///                 else >> "top of stack" or Decl
    MacroUse,

    /// The macro-use-params state.
    ///
    /// This is a nested structure, so when entering this state, it must also be pushed onto the
    /// stack.
    ///
    /// Expected tokens:
    ///                 (0) - .String .Number .MultiLineString >> (1)
    ///                     - .Dollar >> MacroUse
    ///                     - .OpenCurly >> Object
    ///                     - .OpenSquare >> Array
    /// top of stack -> (1) - .String .Number .MultiLineString >> (1)
    ///                     - .Dollar >> MacroUse
    ///                     - .OpenCurly >> Object
    ///                     - .OpenSquare >> Array
    ///                     - .CloseParen >> "top of stack" or Decl
    ///                 else >> Error
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
            while (token.token_type != TokenType.Eof) {
                std.log.err(
                    \\
                    \\State = {}
                    \\Stage = {}
                    \\Stack = 0x{X:0>32} (size = {})
                    \\Token = {}
                    \\
                    , .{self.state, self.state_stage, self.stack, self.stack_size, token.token_type}
                );

                switch (self.state) {
                    .Decl => {
                        switch (token.token_type) {
                            .Dollar => self.state = State.MacroDecl,
                            .String, .Number => self.state = State.KvPair,
                            else => return error.UnexpectedDeclToken,
                        }
                    },

                    // stage   expected tokens  >> next stage/state
                    // --------------------------------------------
                    //     0   String or Number >> 1
                    // --------------------------------------------
                    //     1   OpenParen        >> 2
                    //         Equals           >> 4
                    // --------------------------------------------
                    //     2   String or Number >> 2
                    //         CloseParen       >> 3
                    // --------------------------------------------
                    //     3   Equals           >> 4
                    // --------------------------------------------
                    //     4   String or Number >> Decl
                    //         MultiLineString  >> Decl
                    //         Dollar           >> MacroUse
                    //         OpenCurly        >> Object
                    //         OpenSquare       >> Array
                    .MacroDecl => {
                        switch (self.state_stage) {
                            0 => { // macro key
                                switch (token.token_type) {
                                    .String, .Number => self.state_stage = 1,
                                    else => return error.UnexpectedMacroDeclStage0Token,
                                }
                            },
                            1 => { // parameters or equals
                                switch (token.token_type) {
                                    .OpenParen => self.state_stage = 2,
                                    .Equals => self.state_stage = 4,
                                    else => return error.UnexpectedMacroDeclStage1Token,
                                }
                            },
                            2 => { // parameters
                                switch (token.token_type) {
                                    .String, .Number => {},
                                    .CloseParen => self.state_stage = 3,
                                    else => return error.UnexpectedMacroDeclStage2Token,
                                }
                            },
                            3 => { // equals
                                switch (token.token_type) {
                                    .Equals => self.state_stage = 4,
                                    else => return error.UnexpectedMacroDeclStage3Token,
                                }
                            },
                            4 => { // value
                                switch (token.token_type) {
                                    .String, .Number, .MultiLineString => {
                                        self.state = State.Decl;
                                        self.state_stage = 0;
                                    },
                                    .Dollar => try self.stackPush(stack_macro_use),
                                    .OpenCurly => try self.stackPush(stack_object),
                                    .OpenSquare => try self.stackPush(stack_array),
                                    else => return error.UnexpectedMacroDeclStage4Token,
                                }
                            },
                            else => return error.UnexpectedMacroDeclStage,
                        }
                    },

                    // stage   expected tokens  >> next stage/state
                    // --------------------------------------------
                    //     0   Equals           >> 1
                    // --------------------------------------------
                    //     1   String or Number >> stack or Decl
                    //         MultiLineString  >> stack or Decl
                    //         Dollar           >> MacroUse
                    //         OpenCurly        >> Object
                    //         OpenSquare       >> Array
                    .KvPair => {
                        switch (self.state_stage) {
                            0 => {
                                switch (token.token_type) {
                                    .Equals => self.state_stage = 1,
                                    else => return error.UnexpectedKvPairStage0Token,
                                }
                            },
                            1 => {
                                switch (token.token_type) {
                                    .String, .Number, .MultiLineString => try self.stackPop(),
                                    .Dollar => try self.stackPush(stack_macro_use),
                                    .OpenCurly => try self.stackPush(stack_object),
                                    .OpenSquare => try self.stackPush(stack_array),
                                    else => return error.UnexpectedKvPairStage1Token,
                                }
                            },
                            else => return error.UnexpectedKvPairStage,
                        }
                    },

                    // stage   expected tokens  >> next stage/state
                    // --------------------------------------------
                    //     0   String or Number >> KvPair
                    //         CloseCurly       >> stack or Decl
                    .Object => {
                        switch (token.token_type) {
                            .String, .Number => self.state = State.KvPair,
                            .CloseCurly => try self.stackPop(),
                            else => return error.UnexpectedObjectToken,
                        }
                    },

                    // stage   expected tokens  >> next stage/state
                    // --------------------------------------------
                    //     0   String or Number >> 0
                    //         MultiLineString  >> 0
                    //         Dollar           >> MacroUse
                    //         OpenCurly        >> Object
                    //         OpenSquare       >> Array
                    //         CloseSquare      >> stack or Decl
                    .Array => {
                        switch (token.token_type) {
                            .String, .Number, .MultiLineString => {},
                            .Dollar => try self.stackPush(stack_macro_use),
                            .OpenCurly => try self.stackPush(stack_object),
                            .OpenSquare => try self.stackPush(stack_array),
                            .CloseSquare => try self.stackPop(),
                            else => return error.UnexpectedArrayToken,
                        }
                    },
                    .MacroUse => {},
                    .MacroUseParams => {},
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
const StringParser = Parser(StringReader, 32);

test "temp parse test" {
    const str =
        \\$m1(one two) = {
        \\    hello = $one
        \\    goodbye = $two
        \\}
        \\cool = {
        \\    ports = [ 800 900 ]
        \\    "wh.at" = $m1( 0 $m2( a, b ) ).goodbye
        \\    oh_yea = { thing = \\cool = {
        \\                       \\    ports = [ 800 900 ]
        \\                       \\    what = $m1( 0 $m2( a b ) ).goodbye
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
