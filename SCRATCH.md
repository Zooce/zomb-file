// Simple recursion -- forbidden

$name(n) = {
    name = $name($n)  <-- found outer function used inside the same function
}

// Nested recurssion -- forbidden
//
//  my_name = $name(Zooce)
//
//  -> $name(Zooce) -> $cool_person(Zooce) -> $name(Zooce)
//     ^......................................! Error: `$name` is already in this macro chain. All recursion is forbidden.

$name(n) = {
    name = $cool_person($n)  <-- inner function call also calls the outer function (and vise versa)
}
$cool_person(p) = {
    cool = $name($p)  <-- inner function call also calls the outer function (and vise versa)
}

// Special delimiters that can only be used in KEYs or VALUEs that are double-quoted

'\t' = 0x09 = ✓ -> Horizontal Tab
'\n' = 0x0A = ✓ -> Line Feed
'\r' = 0x0D = ✓ -> Carriage Return
' '  = 0x20 = ✓ -> Space
'"'  = 0x22 = ✓ -> Quotation Mark
'$'  = 0x24 = ✓ -> Dollar Sign
'('  = 0x28 = ✓ -> Left Paren
')'  = 0x29 = ✓ -> Right Paren
','  = 0x2C = ✓ -> Comma
'.'  = 0x2E = ✓ -> Full Stop
'/'  = 0X2F = ✓ -> Solidus (x2)
'='  = 0x3D = ✓ -> Equal Sign
'['  = 0x5B = ✓ -> Left Square
']'  = 0x5D = ✓ -> Right Square
'{'  = 0x7B = ✓ -> Left Curly
'}'  = 0x7D = ✓ -> Right Curly

// Random Notes

To separate key-value pairs, we require a comma, newline, or ending the enclosing set, object, or array with the corresponding right bracket.

// Parsing

STRING = STRING
^----^   ^----^
     |        |...String Value
     |............Identifier

STRING = { STRING = value, DOLLAR STRING = value }
^----^   ^ ^----^   ^---^^ ^-----------^   ^---^ ^
     |   |      |       ||             |       | |...Object End
     |   |      |       ||             |       |...Value (Can be pretty much anything)
     |   |      |       ||             |...Macro Identifier
     |   |      |       ||...Comma (separates key-value pairs)
     |   |      |       |...Value (Can be pretty much anything)
     |   |      |...Identifier
     |   |...Object Begin
     |...Identifier

// -- Macro

DOLLAR STRING = STRING
^-----------^   ^----^
            |        |...String Value
            |............Macro Identifier

// -- Macro Object

DOLLAR STRING = { STRING = value }
^-----------^   ^ ^----^   ^---^ ^
            |   |      |       | |...Object End
            |   |      |       |...Value (Can be pretty much anything)
            |   |      |...Identifier
            |   |...Object Begin
            |...Macro Identifier

// How are we going to parse the tokens?

Stack                  | Token  | Match                    | Action
-----------------------|--------|--------------------------|-------
(empty)                | '$'    | Macro (partial)          | Push
'$'                    | 'name' | Macro (full)             | Push
'$' 'name'             | '('    | Macro Function (partial) | Push
'$' 'name' '('         | 'n'    | Macro Function (partial) | Push
'$' 'name' '(' 'n'     | ')'    | Macro Function (full)    | Push
'$' 'name' '(' 'n' ')' | '='    | None                     | Flush


State {
    MacroId,        // stack = [ DOLLAR, STRING ]
    MacroFuncId,    // stack = [ DOLLAR, STRING, OPEN_PAREN ]
}

Parser {
    parse(tokenizer) {
        while (tokenizer.next()) |token| {
            if (stack.evaluate(token)) {
                stack.push(token)
            } else {
                stack.
            }
        }
    }
}

self.stack = ArrayList.init(&allocator);

token = tokenizer.next();
switch (self.state) {
    .Decl => {
        switch (token) {
            .Dollar => {
                self.stack.push(token);
                token = tokenizer.next();
                if (token != TokenString) {
                    return InvalidMacroIdentifier;
                }
                self.stack.push(token);
                self.state = States.
            },
            .String => self.state = States.Pair,
            .Comment => {},
            else => return Error.InvalidDeclaration,
        }
        self.stack.push(token);
    },
    .MacroId => {
        if (token != Token.String) {
            return InvalidMacroIdentifier,
        }
        self.stack.push(token);
        self.state = States.MacroDecl;
    },
    .MacroDecl => {
        switch (token) {
            .Equals => self.state = States.MacroDef,
            .OpenParen => self.state = States.MacroFuncParam,

        }
    }
}

for (stack) |token| {
    switch (token) {
        .Dollar =>
    }
}

////////

// no params
$macro1 = value
$macro2 = { key = value }
$macro3 = [ value0, value1 ]

key = $macro1  ->  key = value
key = $macro2  ->  key = { key = value }
key = $macro3  ->  key = [ value, value ]

// params
$macro4(a) = $a
$macro5(a) = { key = $a }
$macro6(a) = [ value0, $a ]

key = $macro4(a)  ->  key = a
key = $macro5(a)  ->  key = { key = a }
key = $macro6(a)  ->  key = [ value, a ]

// macro member acccess
key = $macro2.key     ->  key = value
key = $macro3.1       ->  key = value1
key = $macro5(a).key  ->  key = a
key = $macro6(a).0    ->  key = value0


////// Testing out separator syntax

/// No commas - what kinds of weird things can I do

// basics

// this is okay - but depending on the values, might be a little weird
key = [ v1 v2 v3 ]

key = [ v1, v2
    v3]

// this sucks, but that's okay because you can't do this anyways [1]
//  [1]: assignment is defined as `.Equals ws* value .Newline` << a newline is required after an assignment
key = { a = 1 b = 2 c = 3 }

// the macro declaration here is okay - something about no commas between parameters seems weird...
$macro(p1 p2 p3) = {
    a = $p1
    b = $p2
    c = $p3
}

// again this is okay, but something is weird here - maybe commas would be a better idea for parameters
key = $macro(hello there friend)

// ....yea this is better
key = $macro(hello, there, friend)

// we should probably allow this in case we have some longer usage of macros as a parameter..
key = $macro(
    hello,
    there,
    $some_longer_macro
        ( need, more, structure,
          $again_wtf_long_macro_name(for, the, params),
)


////////////////////////////////////////////////////////////////////////////////

1 = {
    11 = [
        112 113
    ]
    12 = $m1 (
            0
            $m2 (
                a
                b
            )
        )
        .key
    13 = {
        131 = $m3
    }
}

.Decl [expect STRING | NUMBER | DOLLAR]
- ('1' .Number) <enter .KvPair>
.KvPair(no-macro) [expect EQUALS]
- ('=' .Equals) [expect VALUE]
- ('{' .OpenCurly) <push .Object> |object <
    .Object [expect STRING | NUMBER | DOLLAR | CLOSE_CURLY]
    - ('11' .Number) <enter .KvPair>
    .KvPair(no-macro) [expect EQUALS]
    - ('=' .Equals) [expect VALUE]
    - ('[' .OpenSquare) <push .Array> |object array <
        .Array [expect VALUE | CLOSE_SQUARE]
        - ('112' .Number) [expect VALUE | CLOSE_SQUARE]
        - ('113' .Number) [expect VALUE | CLOSE_SQUARE]
        - (']' .CloseSquare) <pop .Array> |object <
    .Object [expect STRING | NUMBER | DOLLAR | CLOSE_CURLY]
    - ('12' .Number) <enter .KvPair>
    .KvPair(no-macro) [expect EQUALS]
    - ('=' .Equals) [expect VALUE]
    - ('$' .Dollar) <push .MacroUse> |object use <
        .MacroUse(after=STRING|NUMBER|DOLLAR) [expect STRING | NUMBER | DOLLAR]
        - ('m1' .String) [expect OPEN_PAREN | DOT | OPEN_SQUARE | after]
        - ('(' .OpenParen) <push .MacroParams> |object use params <
            .MacroParams [expect VALUE]
            - ('0' .Number) [expect VALUE | CLOSE_PAREN]
            - ('$' .Dollar) <push .MacroUse> |object use params use <
                .MacroUse(after=CLOSE_PAREN) [expect STRING | NUMBER | DOLLAR]
                - ('m2' .String) [expect OPEN_PAREN | DOT | OPEN_SQUARE | VALUE]
                - ('(' .OpenParen) <push .MacroParams> |object use params use params <
                    .MacroParams [expect VALUE]
                    - ('a' .String) [expect VALUE | CLOSE_PAREN]
                    - ('b' .String) [expect VALUE | CLOSE_PAREN]
                    - (')' .CloseParen) <pop .MacroParams> |object use params use <
                .MacroUse [expect DOT | OPEN_SQUARE]
                - (')' .CloseParen) <pop .MacroUse> |object use params <
            .MacroParams [expect VALUE | CLOSE_PAREN]
            -


    .Object [expect STRING | NUMBER | DOLLAR | CLOSE_CURLY]
    - ('\n' .Newline) <exit .KvPair>
    .Object [expect STRING | NUMBER | DOLLAR | CLOSE_CURLY]
    - ('13' .Number) <enter .KvPair>
    .KvPair [expect EQUALS]
    - ('=' .Equals) [expect VALUE]
    - ('{' .OpenCurly) <push .Object>
        .Object [expect STRING | NUMBER | DOLLAR | CLOSE_CURLY]
        - ('\n' .Newline) [expect STRING | NUMBER | DOLLAR | CLOSE_CURLY]
        - ('131' .Number) <enter .KvPair>
        .KvPair [expect EQUALS]
        - ('=' .Equals) [expect VALUE]
        - ('test' .String) [expect NEWLINE]
        - ('\n' .Newline) <exit .KvPair>
        .Object [expect STRING | NUMBER | DOLLAR | CLOSE_CURLY]
        - ('}' .CloseCurly) <pop .Object>
    .KvPair [expect NEWLINE]
    - ('\n' .Newline) <exit .KvPair>
    .Object [expect STRING | NUMBER | DOLLAR | CLOSE_CURLY]
    - ('}' .CloseCurly) <pop .Object>
.KvPair [expect NEWLINE]

What is a State?

- It has a name (duh).
- It has an entry condition.
- It has an exit condition.
- It has an expected set of the next token.
- A "nested" state can be pushed onto and popped off of a stack.
    - We need this because we'll need to know what State to exit to.

What if `macro-decl` was just a special case of `kv-pair` where we simply keep some meta-data around
if the key of `kv-pair` has a `$` preceeding it? We could set a boolean like `parsing_macro_decl` to
true and then when we enter the .KvPair state, we can expect either an EQUALS or MACRO_DECL_PARAMS.
If we encounter teh MACRO_DECL_PARAMS, then parse those params and save them in whatever data
structure we're using to store macro declarations, then keep parsing .KvPair as usual, but with the
added state of `parsing_macro_decl` we can keep track of where params are used, and then at the end
store the entire macro (which will be used for replacement) into our macro data structure.

Basically, I'm saying, let's treat a macro declaration as a .KvPair but have a boolean indicating
that we need to save this .KvPair in macro data structure.

----

1 = {
    11 = [
        112, 113
    ]
    12 =
        $m1(
            0,
            {
                key = value
                key = [ array, values ]
            },
            $m2(a, b)
        )
    13 = {
        131 = $m3
    }
}


----- Just allow any white space or a comma as the entity delimiter?

key = value key = value
key = { key = value key = value } key = value
key = [ value value value ] key = value
key = [ $macro({ key = value key = value } [ value value ] value) { key = value } ]

key = value, key = value
key = { key = value, key = value }, key = value
key = [ value, value, value, ], key = value
key = [ $macro({ key = value, key = value }, [ value, value ], value), { key = value } ]

--> Here's how this would look with the current restrictions (and some option formatting):

key = value
key = value
key = { key = value
        key = value }
key = value
key = [ value, value, value ]
key = value
key = [ $macro({ key = value
                 key = value }, [ value, value ], value), { key = value
                                                          } ]

-> Minified version of 1

key=value key=value key={key=value key=value}key=value key=[value value value]key=value key=[$macro({key=value key=value}[value value]value){key=value}]


--- What if all macros must have a parameter set (which can be empty)?

$name = Zooce
$colors = {
    black = #000000
    white = $ffffff
}
$ports = [ 800 900 ]
$idk( one two three ) = {
    abc = $one
    def = $two
    ghi = [ $three ]
}

name = $name
foreground = $colors.black
all_colors = $colors
port = $ports[0..]
something = $idk(
    $name
    { key = value }
    $idk( a b $colors.black )
)

// JSON version of above

{
    "name": "Zooce",
    "foreground": "#000000",
    "all_colors": { black: "#000000", white: "#ffffff" },
    "port": [ "800", "900" ],
    "something": {
        "abc": "Zooce",
        "def": { "key": "value" },
        "ghi": {
            "abc": "a",
            "def": "b",
            "ghi": "#000000"
        }
    }
}

// ZOMBIE version of JSON above (without macros)

name = Zooce
foreground = #000000
all_colors = { black = #000000 white = #ffffff }
port = [ 800 900 ]
something = {
    abc = Zooce
    def = { key = value }
    ghi = {
        abc = a
        def = b
        ghi = #000000
    }
}
message = \\This is a multi-line
          \\  string which I'm not sure is that cool
          \\but what do you think?

message = "This is a multi-line"
          "  string which I'm not sure is that cool"
          "but what do you think?" = 1     // this case is a problem

message = "This is a multi-line
  string which I'm not sure is that cool     // leading spaces count toward the string
but what do you think?"
