# Zombie

Welcome! This is the `Zombie` data-file format. It's like JSON but with macros!

## Basics

Here's a basic example:

```
title = Zombie Example

owner = {
    name = Zooce,
    dob = 1988-05-20T00:32:00-08:00,
}

database = {
    enabled = true,
    ports = [ 8000, 8001, 8002 ],
    data = [ [ delta, phi ], [ 3.14 ] ],
    temp_targets = { cpu = 79.5, case = 72.0 },
}

servers = {
    alpha.go = {
        ip = 10.0.0.1,
        role = frontend,
    },
    beta = {
        ip = 10.0.0.2,
        role = backend,
    },
}
```

## Notes

1. Create a `Scanner` to turn the source file into a list of `Token`s
2. Create a `Parser` to turn the list of `Token`s into an AST

## What is a `Token`?

A `Token` is shaped like this:

```
const Token = struct {
    /// the type of the token
    token_type: TokenType,

    /// the actual token string
    lexeme: []const u8,

    /// the line on which this token was scanned
    line: usize,
};

/// These are the types of tokens our `Scanner` will be looking for
const TokenType = enum {
    // single character tokens
    DOLLAR, DOT, EQUAL,
    LEFT_CURLY, RIGHT_CURLY,
    LEFT_PAREN, RIGHT_PAREN,
    LEFT_SQUARE, RIGHT_SQUARE,
    SLASH, QUOTE,

    // literals
    IDENTIFIER, VARIABLE, PARAMETER,

    EOF,
}

What do the nodes of the AST look like?

> _TODO_


# Some ideas from (Eno)[https://eno-lang.org/guide/]

- the first character of a line is special
- arrays are interesting

    instead of [ a, b, c ] they have:
    - a
    - b
    - c

# [NestedText](https://github.com/KenKundert/nestedtext) is quite cool

buf = [MAX_LENGTH]
loop {
    reader.read(buf)
    token = scanner.nextToken()
    stack.push(token)
    if (stack.match()) {
        expr = stack.consume()
    }
}


# Some notes on `File` and its `Reader`

Calling `file.reader()` multiple times, will give back the same reader -- meaning it will still be at the same offset as it was before.

If you want to read from a previous location in the file, use `File`'s `seek*` functions, then use the `Reader` to read.
```

## Debugging with `lldb`

- Install `lldb` with `$ sudo apt install lldb`.
- Start `lldb` with `$ lldb`
- Tell it where the executable is with `$ (lldb) file <path to the executable`
    - The main executable is in `zig-out/bin/zombie-file`
    - The test executable is in `src/zig-cache/o/<hash>/test`
- Place a breakpoint with `$ (lldb) breakpoint set -f <filename (not the path)> -l <line number>`
    - Or `b <filename (not the path)>:<line number>`
- List all the breakpoints with `$ (lldb) br l`
- Run the program with `$ (lldb) r <args>`
- Examine a variable with `$ (lldb) p <variable>`
- Examine all local arguments and variables in the current frame with `$ (lldb) fr v`
- Examine `*self` struct fields with `$ (lldb) v *self`
- Show the current frame and where you are with `$ (lldb) f`
- Continue to the next breakpoint with `$ (lldb) thread continue`
- Delete a breakpoint with `$ (lldb) br del <breakpoint number>`

## Other Tips and Tricks

- How to type a unicde character into Sublime Text on Linux:

    `ctrl+shift+u` > HEX code > `Enter`

    EX: `ctrl+shift+u` > 2713 > `Enter` -> ✓
