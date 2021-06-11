const std = @import("std");

const Tokenizer = @import("token.zig").Tokenizer;
const TokenType = @import("token.zig").TokenType;
const Token = @import("token.zig").Token;

pub const ZombTypeMap = std.StringArrayHashMap(ZombType);
pub const ZombTypeArray = std.ArrayList(ZombType);

pub const ZombType = union(enum) {
    Object: ZombTypeMap,
    Array: ZombTypeArray,
    String: []const u8,
    Empty: void, // just temporary
};

pub const Zomb = struct {
    arena: std.heap.ArenaAllocator,
    map: ZombTypeMap,

    pub fn deinit(self: @This()) void {
        self.arena.deinit();
    }
};

pub const max_stack_size = 64; // this is fairly reasonable (add more stacks if we need more?)

pub const Parser = struct {
    const Self = @This();

    const stack_shift = 2; // 2 bits per stack element

    // stack elements
    //  HEX value combinations ref:
    //                   obj             arr             use             par
    //  obj   0x0 -> obj/obj  0x1 -> obj/arr  0x2 -> obj/use  0x3 -> -------
    //  arr   0x4 -> arr/obj  0x5 -> arr/arr  0x6 -> arr/use  0x7 -> -------
    //  use   0x8 -> -------  0x9 -> -------  0xA -> -------  0xB -> use/par
    //  par   0xC -> par/obj  0xD -> par/arr  0xE -> par/use  0xF -> -------
    const stack_object = 0;
    const stack_array = 1;
    const stack_macro_use = 2;
    const stack_macro_use_params = 3;

    const State = enum {
        Decl,
        MacroDecl,
        KvPair,
        Object,
        Array,
        MacroUse,
        MacroUseParams,
    };

    allocator: *std.mem.Allocator,

    input: []const u8 = undefined,

    tokenizer: Tokenizer,

    state: State = State.Decl,

    // Each state has a set of stages in which they have different expectations of the next token.
    state_stage: u8 = 0,

    // NOTE: the following bit-stack setup is based on zig/lib/std/json.zig
    stack: u128 = 0,
    stack_size: u8 = 0,

    // macros: ZombMacroMap,
    // zomb_type_map: ZombTypeMap,
    zomb_type_stack: ZombTypeArray,
    ml_string: std.ArrayList(u8),

    // cur_macro_decl_key: []const u8 = undefined,

    macro_decl: bool = false,

    pub fn init(input_: []const u8, alloc_: *std.mem.Allocator) Self {
        return Self{
            .allocator = alloc_,
            .input = input_,
            .tokenizer = Tokenizer.init(input_),
            .zomb_type_stack = ZombTypeArray.init(alloc_),
            .ml_string = std.ArrayList(u8).init(alloc_),
        };
    }

    pub fn deinit(self: *Self) void {
        self.zomb_type_stack.deinit();
    }

    pub fn parse(self: *Self) !Zomb {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();

        // our stack has an implicit top-level object
        try self.zomb_type_stack.append(ZombType{ .Object = ZombTypeMap.init(&arena.allocator) });

        var token = try self.tokenizer.next(); // TODO: consider returning null when at_end_of_buffer == true
        parseloop: while (!self.tokenizer.at_end_of_buffer) {
            // NOTE: we deliberately do not get the next token at the start of this loop in cases where we want to keep
            //       the previous token -- instead, we get the next token at the end of this loop

            // ===--- for prototyping only ---===
            std.log.info(
                \\
                \\State      : {} (stage = {})
                \\Bit Stack  : 0x{X:0>32} (size = {})
                \\Type       : {} (line = {})
                \\Token      : {s}
                \\Stack Len  : {}
                \\Macro Decl : {}
                \\Macro Bits : {}
                \\
                // \\Macro Keys: {s}
                \\
                , .{
                    self.state,
                    self.state_stage,
                    self.stack,
                    self.stack_size,
                    token.token_type,
                    token.line,
                    token.slice(self.input),
                    self.zomb_type_stack.items.len,
                    self.macro_decl,
                    self.bitStackHasMacros(),
                    // self.macros.keys(),
                }
            );
            // ===----------------------------===

            // comments are ignored everywhere - make sure to get the next token as well
            if (token.token_type == TokenType.Comment) {
                token = try self.tokenizer.next();
                continue :parseloop;
            }

            switch (self.state) {
                // stage   expected tokens  >> next stage/state
                // --------------------------------------------
                //     -   MacroKey         >> MacroDecl
                //         String or Number >> KvPair
                //         else             >> error
                .Decl => {
                    self.state_stage = 0;
                    switch (token.token_type) {
                        .MacroKey => {
                            // TODO: properly implement macro decls
                            self.macro_decl = true;
                            self.state = State.MacroDecl;
                        },
                        .String, .Number => {
                            self.macro_decl = false;
                            const key = try token.slice(self.input);
                            try self.stackPush(ZombType{ .String = key });
                            self.state = State.KvPair;
                        },
                        else => return error.UnexpectedDeclToken,
                    }
                },

                // stage   expected tokens  >> next stage/state
                // --------------------------------------------
                //     0   OpenParen        >> 1
                //         Equals           >> 3
                //         else             >> error
                // --------------------------------------------
                //     1   String or Number >> -
                //         CloseParen       >> 2
                //         else             >> error
                // --------------------------------------------
                //     2   Equals           >> 3
                //         else             >> error
                // --------------------------------------------
                //     3   MultiLineString  >> 4
                //         String or Number >> Decl
                //         MultiLineString  >> Decl
                //         MacroKey         >> MacroUse
                //         OpenCurly        >> Object
                //         OpenSquare       >> Array
                //         else             >> error
                // --------------------------------------------
                //     4   MultiLineString  >> -
                //         else             >> Decl (keep token)
                .MacroDecl => switch (self.state_stage) {
                    0 => switch (token.token_type) { // parameters or equals
                        .OpenParen => self.state_stage = 1,
                        .Equals => self.state_stage = 3,
                        else => return error.UnexpectedMacroDeclStage0Token,
                    },
                    1 => switch (token.token_type) { // parameters
                        .String, .Number => {},
                        .CloseParen => self.state_stage = 2,
                        else => return error.UnexpectedMacroDeclStage1Token,
                    },
                    2 => switch (token.token_type) { // equals (after parameters)
                        .Equals => self.state_stage = 3,
                        else => return error.UnexpectedMacroDeclStage2Token,
                    },
                    3 => switch (token.token_type) { // value
                        .MultiLineString => {
                            // try self.ml_string.appendSlice(try token.slice(self.input));

                            self.state_stage = 4;
                        },
                        .String, .Number => {
                            // const val = try token.slice(self.input);
                            // try self.stackConsumeKvPair(ZombType{ .String = val });

                            self.state = State.Decl;
                        },
                        .MacroKey => {
                            // TODO: we are currently ignoring macro keys since they will need special treatment
                            // try self.stackConsumeKvPair(ZombType.Empty);
                            try self.bitStackPush(stack_macro_use);
                        },
                        .OpenCurly => {
                            // try self.zomb_type_stack.append(ZombType{ .Object = ZombTypeMap.init(&arena.allocator) });
                            try self.bitStackPush(stack_object);
                        },
                        .OpenSquare => {
                            // try self.zomb_type_stack.append(ZombType{ .Array = ZombTypeArray.init(&arena.allocator) });
                            try self.bitStackPush(stack_array);
                        },
                        else => return error.UnexpectedMacroDeclStage3Token,
                    },
                    4 => switch (token.token_type) {
                        .MultiLineString => {
                            // try self.ml_string.appendSlice(try token.slice(self.input));
                        },
                        else => {
                            // try self.stackConsumeKvPair(ZombType{ .String = self.ml_string.toOwnedSlice() });

                            self.state = State.Decl;
                            continue :parseloop; // we want to keep the current token
                        },
                    },
                    else => return error.UnexpectedMacroDeclStage,
                },

                // stage   expected tokens  >> next stage/state
                // --------------------------------------------------
                //     0   Equals           >> 1
                //         else             >> error
                // --------------------------------------------------
                //     1   MultiLineString  >> 2
                //         String or Number >> Object (stack) or Decl
                //         MacroKey         >> MacroUse
                //         OpenCurly        >> Object
                //         OpenSquare       >> Array
                //         else             >> error
                // --------------------------------------------------
                //     2   MultiLineString  >> -
                //         else             >> Object (stack) or Decl (keep token)
                .KvPair => switch (self.state_stage) {
                    0 => switch (token.token_type) {
                        .Equals => self.state_stage = 1,
                        else => return error.UnexpectedKvPairStage0Token,
                    },
                    1 => switch (token.token_type) {
                        .MultiLineString => {
                            if (!self.macro_decl and !self.bitStackHasMacros()) {
                                try self.ml_string.appendSlice(try token.slice(self.input));
                            }
                            self.state_stage = 2; // wait for more lines in stage 2
                        },
                        .String, .Number => {
                            if (!self.macro_decl and !self.bitStackHasMacros()) {
                                const val = try token.slice(self.input);
                                try self.stackConsumeKvPair(ZombType{ .String = val });
                            }

                            if (self.bitStackPeek()) |stack_type| {
                                self.state_stage = 0;
                                switch (stack_type) {
                                    stack_object => self.state = State.Object,
                                    else => return error.UnexpectedKvPairBitStackPeek,
                                }
                            } else {
                                self.state = State.Decl;
                            }
                        },
                        .MacroKey => {
                            // TODO: we are currently ignoring macro keys since they will need special treatment
                            if (!self.macro_decl and !self.bitStackHasMacros()) try self.stackConsumeKvPair(ZombType.Empty);
                            try self.bitStackPush(stack_macro_use);
                        },
                        .OpenCurly => {
                            if (!self.macro_decl and !self.bitStackHasMacros()) try self.zomb_type_stack.append(ZombType{ .Object = ZombTypeMap.init(&arena.allocator) });
                            try self.bitStackPush(stack_object);
                        },
                        .OpenSquare => {
                            if (!self.macro_decl and !self.bitStackHasMacros()) try self.zomb_type_stack.append(ZombType{ .Array = ZombTypeArray.init(&arena.allocator) });
                            try self.bitStackPush(stack_array);
                        },
                        else => return error.UnexpectedKvPairStage1Token,
                    },
                    2 => switch (token.token_type) {
                        .MultiLineString => if (!self.macro_decl and !self.bitStackHasMacros()) {
                            try self.ml_string.appendSlice(try token.slice(self.input));
                        },
                        else => {
                            if (!self.macro_decl and !self.bitStackHasMacros()) {
                                try self.stackConsumeKvPair(ZombType{ .String = self.ml_string.toOwnedSlice() });
                            }

                            if (self.bitStackPeek()) |stack_type| {
                                self.state_stage = 0;
                                switch (stack_type) {
                                    stack_object => self.state = State.Object,
                                    else => return error.UnexpectedKvPairBitStackPeek,
                                }
                            } else {
                                self.state = State.Decl;
                            }

                            continue :parseloop; // we want to keep the current token
                        },
                    },
                    else => return error.UnexpectedKvPairStage,
                },

                // stage   expected tokens  >> next stage/state
                // --------------------------------------------
                //     -   String or Number >> KvPair
                //         CloseCurly       >> stack or Decl
                //         else             >> error
                .Object => switch (token.token_type) {
                    .String, .Number => {
                        if (!self.macro_decl and !self.bitStackHasMacros()) {
                            const key = try token.slice(self.input);
                            try self.stackPush(ZombType{ .String = key });
                        }
                        self.state = State.KvPair;
                    },
                    .CloseCurly => {
                        try self.bitStackPop();
                        if (!self.macro_decl and !self.bitStackHasMacros()) {
                            switch (self.bitStackPeek() orelse stack_object) {
                                stack_object => try self.stackConsumeKvPair(self.zomb_type_stack.pop()),
                                stack_array => try self.stackConsumeArrayValue(self.zomb_type_stack.pop()),
                                else => return error.UnexpectedObjectBitStackPeek,
                            }
                        }
                    },
                    else => return error.UnexpectedObjectToken,
                },

                // stage   expected tokens  >> next stage/state
                // --------------------------------------------
                //     0   String or Number >> -
                //         MultiLineString  >> 1
                //         MacroKey         >> MacroUse
                //         OpenCurly        >> Object
                //         OpenSquare       >> Array
                //         CloseSquare      >> stack or Decl
                //         else             >> error
                // --------------------------------------------
                //     1   MultiLineString  >> -
                //         else             >> 0 (keep token)
                .Array => switch (self.state_stage) {
                    0 => switch (token.token_type) {
                        .String, .Number => if (!self.macro_decl and !self.bitStackHasMacros()) {
                            const val = try token.slice(self.input);
                            try self.stackConsumeArrayValue(ZombType{ .String = val });
                        },
                        .MultiLineString => {
                            if (!self.macro_decl and !self.bitStackHasMacros()) {
                                try self.ml_string.appendSlice(try token.slice(self.input));
                            }
                            self.state_stage = 1;
                        },
                        .MacroKey => {
                            try self.bitStackPush(stack_macro_use);
                        },
                        .OpenCurly => {
                            if (!self.macro_decl and !self.bitStackHasMacros()) try self.zomb_type_stack.append(ZombType{ .Object = ZombTypeMap.init(&arena.allocator) });
                            try self.bitStackPush(stack_object);
                        },
                        .OpenSquare => {
                            if (!self.macro_decl and !self.bitStackHasMacros()) try self.zomb_type_stack.append(ZombType{ .Array = ZombTypeArray.init(&arena.allocator) });
                            try self.bitStackPush(stack_array);
                        },
                        .CloseSquare => {
                            try self.bitStackPop();
                            if (!self.macro_decl and !self.bitStackHasMacros()) {
                                switch (self.bitStackPeek() orelse stack_object) {
                                    stack_object => try self.stackConsumeKvPair(self.zomb_type_stack.pop()),
                                    stack_array => try self.stackConsumeArrayValue(self.zomb_type_stack.pop()),
                                    else => return error.UnexpectedTypeFromBitStackPeek,
                                }
                            }
                        },
                        else => return error.UnexpectedArrayStage0Token,
                    },
                    1 => switch (token.token_type) {
                        .MultiLineString => if (!self.macro_decl and !self.bitStackHasMacros()) {
                            try self.ml_string.appendSlice(try token.slice(self.input));
                        },
                        else => {
                            if (!self.macro_decl and !self.bitStackHasMacros()) {
                                try self.stackConsumeArrayValue(ZombType{ .String = self.ml_string.toOwnedSlice() });
                            }

                            self.state_stage = 0;
                            continue :parseloop; // we want to keep the current token
                        },
                    },
                    else => return error.UnexpectedArrayStage,
                },

                // stage   expected tokens  >> next stage/state
                // --------------------------------------------
                //     0   String or Number >> 1
                //         else             >> error
                // --------------------------------------------
                // >>> 1   Dot              >> 0
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
                        .OpenParen => try self.bitStackPush(stack_macro_use_params),
                        else => {
                            try self.bitStackPop();
                            continue :parseloop; // we want to keep the current token
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
                //         MultiLineString  >> 2
                //         MacroKey         >> MacroUse
                //         OpenCurly        >> Object
                //         OpenSquare       >> Array
                //         else             >> error
                // --------------------------------------------
                // pop 1   String or Number >> -
                //         MultiLineString  >> -
                //         MacroKey         >> MacroUse
                //         OpenCurly        >> Object
                //         OpenSquare       >> Array
                //         CloseParen       >> stack or Decl
                //         else             >> error
                // --------------------------------------------
                //     2   MultiLineString  >> -
                //         else             >> 1 (keep token)

                // TODO: how do we handle these?
                .MacroUseParams => switch (self.state_stage) {
                    0 => switch (token.token_type) { // we require at least one parameter if we're here
                        .String, .Number => self.state_stage = 1,
                        .MultiLineString => self.state_stage = 2,
                        .MacroKey => try self.bitStackPush(stack_macro_use),
                        .OpenCurly => try self.bitStackPush(stack_object),
                        .OpenSquare => try self.bitStackPush(stack_array),
                        else => return error.UnexpectedMacroUseParamsStage0Token,
                    },
                    1 => switch (token.token_type) { // more than one parameter
                        .String, .Number, => {},
                        .MultiLineString => {},
                        .MacroKey => try self.bitStackPush(stack_macro_use),
                        .OpenCurly => try self.bitStackPush(stack_object),
                        .OpenSquare => try self.bitStackPush(stack_array),
                        .CloseParen => try self.bitStackPop(),
                        else => return error.UnexpectedMacroUseParamsStage1Token,
                    },
                    2 => switch (token.token_type) { // more lines of a multi-line string
                        .MultiLineString => {},
                        else => continue :parseloop,
                    },
                    else => return error.UnexpectedMacroUseParamsStage,
                },
            }

            token = try self.tokenizer.next();
        } // end :parseloop

        return Zomb{
            .arena = arena,
            .map = self.zomb_type_stack.pop(),
        };
    }

    fn stackPush(self: *Self, zomb_type_: ZombType) !void {
        try self.zomb_type_stack.append(zomb_type_);
    }

    fn stackConsumeKvPair(self: *Self, zomb_type_: ZombType) !void {
        const key = self.zomb_type_stack.pop();
        var object = &self.zomb_type_stack.items[self.zomb_type_stack.items.len - 1].Object;
        try object.put(key.String, zomb_type_);
    }

    fn stackConsumeArrayValue(self: *Self, zomb_type_: ZombType) !void {
        var array = &self.zomb_type_stack.items[self.zomb_type_stack.items.len - 1].Array;
        try array.append(zomb_type_);
    }

    fn bitStackPush(self: *Self, stack_type: u2) !void {
        if (self.stack_size > max_stack_size) {
            return error.TooManyBitStackPushes;
        }
        self.stack <<= stack_shift;
        self.stack |= stack_type;
        self.stack_size += 1;
        self.state_stage = 0;
        switch (stack_type) {
            stack_object => self.state = State.Object,
            stack_array => self.state = State.Array,
            stack_macro_use => {
                // we always enter MacroUse in stage 1
                self.state = State.MacroUse;
                self.state_stage = 1;
            },
            stack_macro_use_params => self.state = State.MacroUseParams,
        }
    }

    fn bitStackPop(self: *Self) !void {
        if (self.stack_size == 0) {
            return error.TooManybitStackPops;
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

    fn bitStackPeek(self: Self) ?u2 {
        if (self.stack_size == 0) {
            return null;
        }
        return @intCast(u2, self.stack & 0b11);
    }

    fn bitStackHasMacros(self: Self) bool {
        return (self.stack & 0x2222_2222_2222_2222_2222_2222_2222_2222) > 0;
    }
};

//==============================================================================
//
//
//
// Testing
//==============================================================================

const testing = std.testing;

const StringReader = @import("string_reader.zig").StringReader;
const StringParser = Parser(StringReader, 32);

test "stack logic" {
    var stack: u128 = 0;
    var stack_size: u8 = 0;
    const stack_size_limit: u8 = 64;
    const shift = 2;
    const obj = 0;
    const arr = 1;
    const mac = 2;
    const par = 3;

    try testing.expectEqual(@as(u128, 0x0000_0000_0000_0000_0000_0000_0000_0000), stack);

    // This loop should push 0, 1, 2, and 3 in sequence until the max stack size
    // has been reached.
    var t: u8 = 0;
    while (stack_size < stack_size_limit) {
        stack <<= shift;
        stack |= t;
        stack_size += 1;
        t = (t + 1) % 4;
        if (stack_size != stack_size_limit) {
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
