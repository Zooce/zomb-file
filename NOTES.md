# TODOs

- keep working on quoted string token parsing and testing



---


## Debugging with `lldb`

- Install `lldb` with `$ sudo apt install lldb`.
- Start `lldb` with `$ lldb`
- Tell it where the executable is with `$ (lldb) file <path to the executable`
    - The main executable is in `zig-out/bin/zombie-file`
    - Tests are a little different, just do this:
        - Make a temp directory: `$ mkdir .testbins && echo ".testbins" >> .gitignore`
        - Build the tests you want with `$ zig test src/<file>.zig -femit-bin=./.testbins/<file>-test`
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

Basic Commands
- `r` = run the exectuable
- `n` = step over
- `s` = step into
- `c` = continue
- `f` = step out
- `v` = print local variables and function arguments
- `p <expr>` = print result of `<expr`

## Other Tips and Tricks

- How to type a unicde character into Sublime Text on Linux:

    `ctrl+shift+u` > HEX code > `Enter`

    EX: `ctrl+shift+u` > 2713 > `Enter` -> ✓

## Parsing State Machine

> The current state tells us what we have on the stack.

Current State > Token > Next State

.None > STRING > .Id
.None > DOLLAR > .MacroIdPrefix
.None > COMMENT > .None

.Id > EQUAL > .Assigment

.MacroIdPrefix > STRING > .MacroId

.MacroId > EQUAL > .MacroDecl
.MacroId > OPEN_PAREN > .MacroFuncId

.MacroDecl > STRING > .MacroValue
.MacroDecl > OPEN_CURLY > .ObjectBegin
