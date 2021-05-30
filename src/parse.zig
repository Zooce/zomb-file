const std = @import("std");

const makeTokenizer = @import("token.zig").makeTokenizer;
const TokenType = @import("token.zig").TokenType;
const Token = @import("token.zig").Token;

// TODO: be more specific with the error types
pub const ParserError = error {
    InvalidDeclaration,
    MissingKvPairString,
    InvalidAssignment,
    InvalidValue,
    MissingObjectClosingCurly,
    MissingComma,
    InvalidStackKind,
    TooManyStackItems,
};

pub fn makeParser(file: anytype) Parser(@TypeOf(file)) {
    return .{ .file = file };
}

pub fn Parser(comptime FileType: type) type {
    return struct {
        file: FileType,

        state: State = State.Decl,

        parent: Parent = Parent.None,

        // NOTE: the following bit-stack setup is taken from zig/lib/std/json.zig
        // Bit-stack for nested object/map literals (max 128 nestings).
        stack: u256,
        stack_size: u8,

        const object_val = 0;
        const array_val = 1;
        const macro_val = 2;
        const max_stack_size = 128; // realistically, this is reasonable

        pub fn parse(self: *Parser) !void {
            var tokenizer = makeTokenizer(file)
            while (true) {
                var token = try tokenizer.next();
                switch (self.state) {
                    .Decl => {
                        switch (token.token_type) {
                            .String => self.state = State.KvPair,
                            .Dollar => self.state = State.MacroDecl,
                            .Comment => {},
                            else => return ParserError.InvalidDeclaration;
                        }
                    },

                    .MacroDecl => {
                        // TODO: something
                    };

                    .KvPair => {
                        if (self.parent = Parent.Object and token.token_type == TokenType.CloseCurly) {
                            self.stackPop();
                            if (self.parent == Parent.Array) {
                                self.state = State.Comma;
                            } else {
                                self.state = State.Newline;
                            }
                        } else if (token.token_type != TokenType.String) {
                            return ParserError.MissingKvPairString;
                        }
                        self.state = State.Assignment;
                    },

                    .Assignment => {
                        if (token.token_type != TokenType.Equals) {
                            return ParserError.InvalidAssignment;
                        }
                        self.state = State.Value;
                    }

                    .Value {
                        switch (token.token_type) {
                            .String, .Number => {
                                if (self.stack & array_val == array_val) {
                                    self.state = State.Comma;
                                } else {
                                    self.state = State.Newline;
                                }
                            },
                            .OpenCurly => {
                                self.stackPush(object_val);
                                self.state = State.KvPair;
                                self.parent = Parent.Object;
                            },
                            .OpenSquare => {
                                self.stackPush(array_val);
                                self.state = State.Value;
                                self.parent = Parent.Array;
                            },
                            .Dollar => {
                                self.stackPush(macro_val);
                                self.state = State.MacroUseKey;
                                self.parent = Parent.Macro;
                            },
                            .CloseSquare => {
                                if (self.parent != Parent.Array) {
                                    return ParserError.InvalidValue;
                                }
                                self.stackPop();
                                self.state = State.Separator;
                            },
                            else => return ParserError.InvalidValue,
                        }
                    }

                    .MacroUseKey => {
                        // TODO: something
                    }

                    .Comma => {
                        switch (token.token_type) {
                            .CloseSquare => {
                                // this is okay if the parent is an array
                            },
                            .CloseParen => {
                                // this is okay if the parent is macro
                            },
                            .Comma => {},
                            else => return ParserError.MissingComma,
                        }
                    }

                    .Newline => {

                    }

                    .Separator => {
                        switch (token.token_type) {
                            .Comma => {
                                if (self.stack & array_val != array_val and self.stack & macro_val != macro_val) {
                                    return ParserError.UnexpectedComma;
                                }
                            }
                            .Newline => {
                                if (self.stack & )
                            },
                            else => return ParserError.MissingSeparator;
                        }

                        // TODO: If we get here, then whatever we just parsed is valid and we should now execute
                        //       the directive corresponding to the current mode: e.g. translate to JSON.

                        if (self.stack & object_val == object_val) {
                            // we're still parsing an object, so look for another KvPair
                            self.state = State.KvPair;
                        } else if (self.stack & array_val == array_val) {
                            // we're still parsing an array, so look for another Value
                            self.state = State.Value;
                        } else {
                            // we weren't parsing an object or an array
                        }
                    }

                    else => {},
                }
            }
            // get the next token from the Tokenizer

            // the current state represents the production we think we're currently parsing
        }

        fn stackPush(self: *Parser, kind: u2) !void {
            if (self.stack_size == max_stack_size) {
                return ParserError.TooManyStackItems;
            }
            self.parent = switch (kind) {
                object_val => Parent.Object,
                array_val => Parent.Array,
                macro_val => Parent.Macro,
                else => return ParserError.InvalidStackKind;
            }
            self.stack <<= 2;
            self.stack |= kind;
            self.stack_size += 1;
        }

        fn stackPop(self: *Parser) void {
            self.stack >>= 2;
            self.stack_size -= 1;

            if (self.stack_size == 0) {
                self.parent = Parent.None;
            } else {
                if (self.stack & object_val == object_val) {
                    self.parent = Parent.Object;
                } else if (self.stack & array_val == array_val) {
                    self.parent = Parent.Array;
                } else if (self.stack & macro_val == array_val) {
                    self.parent = Parent.Macro;
                } else {
                    unreachable;
                }
            }
        }
    };
}

/// This state represents what the parser is currently looking for.
const State = enum {
    Decl,

    MacroDecl,
    KvPair,

    Assignment,

    Value,

    MacroUseKey,

    Comma,
    Newline,
};

const Parent = enum {
    None,
    Object,
    Array,
    Macro,
};

//==============================================================================
//
//
//
// Testing
//==============================================================================

// TODO
