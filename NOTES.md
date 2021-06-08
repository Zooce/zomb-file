# TODOs

- Translate to JSON....
- Better test cases
    - kv-pair
        string = number
        string = string
        string = ml-string
        string = empty object
        string = object
        string = empty array
        string = array
        string = macro-use (+ all combos of params|keys|ranges)
        number = number
        number = string
        ...
    - object
        object in an object
        object in an array
        object in a macro-use
    - array
        array in an object
        array in an array
        array in a macro-use
    - ml-string
        ml-string in an object
        ml-string in an array
        ml-string in a macro-use
    - bare-string
        ?
    - quoted-string
        ?

----

# ROADMAP

- Include a CLI that allows the user to do the following:
    - Convert a given ZOMBIE file to:
        - JSON
        - TOML
        - YAML
    - Given a ZOMBIE file, produce another ZOMBIE file with all macros evaluated
    - Format a given ZOMBIE file based on either the rules defined in a ZOMBIE-FMT file or a default set of heuristics
- Create a C-ABI compatible library for reading and writing ZOMBIE files
    - Parsing API Ideas:
        - zomb_parser.next() // tell the parser to process the next token
        - zomb_parser.state() // ask the parser what it's currently parsing
        - zomb_parser.fastForwardTo(key) // move the parser to the next occurrence of "key"
        - zomb_parser.rewindTo(key) // move the parser back to the previous occurrence of "key"
        - How would this API be used?
            - ref: https://stackoverflow.com/questions/17244488/reading-struct-in-python-from-created-struct-in-c
            ```python
            from ctypes import cdll
            zomb_parser = cdll.LoadLibrary('libzomb.so')

            def load(fd):
                parser = zomb_parser.init(fd)
                # root = parser.parse_all()
                status = parser.next()
                while status.state != zomb_parser.state.Eof:

            ```
        - Can we do this with a streaming API? Maybe the calling code passes the `ZombTree` structure to the parser each time it wants more data, and the parser gradually fills out the `ZombTree` as it parses more tokens?
            ```python
            import ctypes
            zomb_parser = cdll.LoadLibrary('libzomb.so')

            # ... other structures/unions that must be defined

            class ZombTree(ctypes.Structure):
                _fields_ = [
                    ("root", ZombTreeNode),
                    # ... other fields on the ZombTree
                ]

                def to_dict(self):
                    d = {}
                    # ... start from "root" and fill out the dictionary
                    return d

            def parse(fd):
                tree = ZombTree()
                parser = zomb_parser.ZombFileParser.init(fd)
                while not parser.finished {
                    parser.next(tree)
                }

                return tree.to_dict()
            ```
        - Is having a parsing API even useful at all?

    - Maybe also create the bindings for popular languages:
        - Python
        - Rust
        - C/C++ (would they be able to just use the Zig C-ABI one directly?)
        - What else?

---


## Debugging with `lldb`

- Install `lldb` with `$ sudo apt install lldb`.
- Build a test and add it to `lldb` with:
    - `zig test [--test-filter "<test filter string>"] src/<file>.zig --test-cmd lldb --test-cmd-bin`
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
- `b <file>:<line>` = set a breakpoint in `<file>` on line `<line>`

## Other Tips and Tricks

- How to type a Unicode character into Sublime Text on Linux:

    `ctrl+shift+u` > HEX code > `Enter`

    EX: `ctrl+shift+u` > 2713 > `Enter` -> ✓
