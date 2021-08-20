# The ZOMB file format

Welcome to the ZOMB file format specification. It's sort of a 90/10 mix of JSON and TOML...plus a small, useful set of special features!

> _Similar to how JSON is pronounced "J-son", ZOMB is pronounced "zom-B" 🧟._

> _Why did I make this? Read about it in the [Why](#why) section._

## General Rules, Guidelines, and Definitions

- ZOMB files are UTF-8 encoded text files
- ZOMB files typically have a `.zomb` extension
- "Whitespace" is defined as a tab (U+0009) or a space (U+0020)
- "Newline" is defined as an LF (U+000A) or a CRLF (U+000D U+000A)
- Whitespace and newlines are ignored unless stated otherwise
- Commas as separators are optional - (see [Why](#why))

## Key-Value Pairs

A key-value pair associates a key (which is a string) with a value.

```zomb
key = value
```

> _Keys at the same level must be unique._

> _Using `=` as the separator is taken from the [TOML](https://toml.io/en/) file format._

### Value Types

There are only three value types:

- [String](#strings)
- [Object](#objects)
- [Array](#arrays)

## Strings

Strings can be simple and yet they have plenty of complicated scenarios. ZOMB files deal with this by placing strings in three categories:

- [Bare String](#bare-strings): A string containing no special delimiters
- [Quoted String](#quoted-strings): A string that may contain special delimiters and escape sequences
- [Raw String](#raw-strings): A string that may contain any characters with no restrictions

> _Why not just quoted strings like in JSON? Read about it in the [Why](#why) section._

### Bare Strings

A bare string may contain any Unicode code point except any of these special delimiters:

- Unicode control characters (U+0000 through U+001F -- this includes tabs and newlines)
- ` `, `,`, `.`, `"`, `\` (U+0020, U+002C, U+002E, U+0022, U+005C)
- `$`, `%`, `+`, `=`, `?` (U+0024, U+0025, U+002B, U+003D, U+003F)
- `(`, `)`, `[`, `]`, `{`, `}` (U+0028, U+0029, U+005B, U+005D, U+007B, U+007D)

```zomb
key = a_bare_string
```

```zomb
key = not a bare string  // this is an error!
```

### Quoted Strings

If you want to include any of the special delimiters not allowed in bare strings, excluding newlines, then you can surround the string with quotation marks -- standard escape sequences apply.

```zomb
key = "a_quoted_string"  // this is fine, but unnecessary
```

```zomb
key = "a quoted string"  // this _is_ necessary
```

```zomb
"this is okay too" = value
```

> _Keys (since they're strings too) may also be quoted._

> _The quotation marks (`"`) are only delimiters and are not part of the string's actual value._

### Raw Strings

For fun, let's describe these in a couple of examples:

```zomb
dialog = \\This is a raw string. Raw strings start with '\\' and run to the end
         \\of the line. They continue until either an empty line or a non-raw
         \\string token is encountered.
         \\
         \\Raw strings may contain any characters without the need for an escape
         \\sequence.
         \\
         \\Newlines are included in raw strings except for the very last one.
```

```zomb
dialog = \\blah blah
         \\blah blah

         \\this is an ERROR
```

```zomb
\\Raw strings CANNOT
\\be used as keys
= value
```

> _The leading backslashes (`\\`) are only delimiters and are not part of the string's actual value._

> _Using `\\` as the delimiter is taken from the [Zig](https://ziglang.org) programming language._

### _Empty Strings_

Empty strings are allowed, but they only work if they're quoted or raw.

```zomb
// empty quoted string - okay
key = ""
```

```zomb
// empty raw string - okay
key = \\
```

```zomb
// empty bare string - obviously an error!
key =
```

## Objects

Objects group a set of [key-value](#key-value-pairs) pairs inside a pair of curly braces.

```zomb
file = {
    type = ZOMB
    path = "/home/zooce/passwords.zomb"  // DON'T STORE YOUR PASSWORDS LIKE THIS!
}
```

```zomb
key = {}  // empty objects are okay
```

> _Keys in the same object must be unique._

## Arrays

Arrays group a set of [values](#value-types) inside square brackets.

```zomb
"people jobs" = [
    Hacker
    Dishwasher
    "Dog Walker"
]
```

```zomb
key = []  // empty arrays are okay
```

## Wait there's more!

Congratulations! With the knowledge you've gained so far, you can write a valid ZOMB file. Key-value pairs, objects, arrays, strings...easy. However, I hope you're wondering something like, "That's it? I mean it's basically just a _really nice_ variant of JSON. _(And the person who made this is brilliant.)_"

Alright, let's get to some of the extra features of ZOMB files:

- [Concatenation](concatenation)
- [Comments](comments)
- [Macros](macros)

## Concatenation

ZOMB files allow same-type value concatenation (string-string, object-object, and array-array) with the `+` operator. The following examples are boring, but they get the point across.

```zomb
key = bare_string + "quoted string" + \\raw-
                                      \\string
```

```zomb
key = { a = hello } + { b = world }
```

> _Keys in the resulting object must be unique._

```zomb
key = [ 1 2 3 ] + [ 4 5 6 ]
```

## Comments

You've already seen comments in the previous examples, but now you know that comments are a real thing!

Comments start with `//` and run to the end of the line.

```zomb
// this is a comment on its own line

hello = goodbye // this is a comment at the end of a line

key = [ // comments can be pretty much anywhere
    1 2 3
]
```

## Macros

If you've made it this far, you're _awesome_ and I think you'll find this feature awesome too. You're about to learn what makes ZOMB files worth your time.

Macros are the special sauce of ZOMB files. They allow you to write reusable (and optionally, parameterized) values. Let's start with an example:

```zomb
$color = {
    black = #000000
    red = #ff0000
    hot_pink = #ff43a1
}
// sometimes commas are nice (still not required though)
$colorize(scope, color = $color.black) = {
    scope = %scope
    settings = { foreground = %color }
}
tokenColors = [
    $colorize("editor.background")
    $colorize("editor.foreground", $color.red)
    $colorize("comments", $color.hot_pink)
]
```

There's a lot going on there, but I bet you already kind of get it.

### Defining a Macro

Macros are defined just like key-value pairs, but with some special rules.

#### Location

Macros can only be defined at the top-level, meaning macros may _not_ be defined inside any other value.

#### Macro Keys

The key for a macro can be either a bare string or a quoted string, but with a leading dollar sign (`$`).

```zomb
$macro1 = Hello
$"macro two" = Goodbye
```

#### Macro Parameters

Macros can have a set of parameters declared inside a set of parentheses after the key. Parameters are accessible inside the macro by placing a percent sign (`%`) before the parameter name.

A couple of sub-rules:
- An empty set of parentheses is **invalid**
- Each parameter _must_ be used at least once in the macro's value

```zomb
$macro(p1 p2) = [ %p1 %p2 ]
```

Macro parameters can have default values. All parameters _without_ default values must come **before** those _with_ default values.

```zomb
$macro(p1, p2 = 4, p3 = [ a b c ]) = {
    a = %p1
    b = %p2
    c = %p3
}
```

```zomb
// Error: parameters with no default value must come first
$macro(p1 = 2, p2) = [ %p1, %p2 ]
```

#### (No) Recursion

Recursion in macro definitions is forbidden. _These examples will also give you a preview on how to use macros after you've defined them._

```zomb
$name = $name  // not cool
```

```zomb
$macro1(p1 p2) = {
    this = %p1
    that = $macro2(%p2) // this uses `$macro1` -- forbidden
}
$macro2(a) = $macro1(%a, 5)
// this example also violates the definition-before-use rule (keep reading)
```

```zomb
$okay(param) = [ 1 2 %param 3 ]

// this _is_ okay, because it is not recursion
my_key = $okay($okay(4))
```

### Using a Macro

To use a macro as a value, called a "Macro Expression", you specify its key (including the `$`).

> _You must define a macro before it is used as a value. This helps keep implementation simple, and most of the time helps with readability._

```zomb
$name = Gene

names = [
    Fred
    Kara
    $name  // easy
    Tommy
]
```

If the macro has parameters, you pass in a value for each inside a set of parentheses. Parameter values can be any type and must be given in the order in which they are defined.

```zomb
$person(name, job) = {
    name = %name
    job = %job
}

"cool person" = $person(Zooce, { type = Dishwasher, pay = 100000 })
```

If one or more of the macro's parameters has default values, you may use the default values by _not_ passing in values for them.

```zomb
$item(id, label = null) = {
    id = %id
    label = %label
}

items = [
    $item(abc)
    $item(def, "Cool Beans")
]
```

If you pass a value for a parameter with a default value, then you must also pass values for all parameters preceding that one.

```zomb
$test(a, b=1, c=2) = [ %a %b %c ]

t = test(3, 4) // [ 3 4 2 ]
```

If the macro's value is an object or an array, you can access individual keys or indexes (and even the keys or indexes of nested objects and arrays) by following the macro expression with one or more access patterns like `.key` or `.2` for example.

> _You may **NOT** access individual keys or indexes of parameter values (e.g., `%a.key`). Why? Because you can pass any value as a parameter argument, so there's no guarantee it will conform to the access pattern -- remember, this is **not** a full-fledged programming language._

```zomb
$person(name, job) = {
    name = %name
    job = {
        title = %job
        pay = "1,000,000"
        coworkers = [ Linz, Beegs, Bug, Munchy, Xena ]
    }
}

last_coworker = $person(Zooce, Dishwasher).job.coworkers.3
```

### Batching Macro Expressions

Here's where things get even cooler. What if you want to use a macro many times where only a subset of the parameters change? With macro batching you can apply a set of arguments for a subset of parameters while keeping other parameters static. Let's show this by an example.

Say we define the following two macros:

```zomb
$color = {
    black = #000000
    red = #ff0000
}
$colorize(scope, color, alpha) = {
    scope = %scope
    settings = { foreground = %color + %alpha }
}
```

One way we might use these is like this:

```zomb
tokenColors = [
    // things I want colored in black
    $colorize("editor.background", $color.black, 55)
    $colorize("editor.border", $color.black, 66)
    // ... many more

    // things I want colored in red
    $colorize("editor.foreground", $color.red, 7f)
    $colorize("editor.highlightBorder", $color.red, ff)
    // ... many more
]
```

This is fine, but if we have many of these `$colorize` macro expressions we kind of have another repetition problem. With macro batching we can do better:

```zomb
tokenColors =
    $colorize(?, $color.black, ?) % [
        [ "editor.background" 55 ]
        [ "editor.border"     66 ]
        // ... many more
    ] +
    $colorize(?, $color.red, ?) % [
        [ "editor.foreground"      7f ]
        [ "editor.highlightBorder" ff ]
        // ... many more
    ]
```

There's a couple things you probably figured out:

- The parameters we want to vary have a `?` in their place.
- The set of arguments we want to apply are specified in a two-dimensional array after the `%` delimiter.
- The batched macro results in an array, so we can chain batches together with concatenation (`+`).

One bonus of this is that it even kind of eliminates the need for those `// things I want colored in <color>` comments as it's somewhat self documenting.

## And that's it!

So, what do you think? Like it? Hate it? Either way, I hope you at least enjoyed learning about this little file format. It's useful to me and I certainly hope it's useful for you.

# Current Implementations and Utilities

- [`zomb-zig`](https://github.com/Zooce/zomb-zig): ZOMB reader/writer library
- _planning on a Python implementation_
- _planning on a ZOMB to JSON/TOML/YAML utility_

> _Hopefully even more coming soon!_

# Why

## Why was the ZOMB file format created?

If you've ever maintained a color scheme for either Sublime Text or VS Code then you know how unwieldy the repetition becomes in those JSON files. I tried looking for other file formats that would reduce the repetition which I could then convert to JSON, and that didn't pan out. Then I tried creating a little text-replacement script that would parse, extract, and replace special reusable patterns in comments and strings -- that helped, but didn't really solve the problem.

So, since I didn't have a solution I was satisfied with, I figured I'd have some fun and create something new, and here you are reading about it now!

However, if you've read through this file in its entirety, you'll notice that the ZOMB file format can be used for pretty much anything that JSON, TOML, YAML, and other generic data file formats are useful for.

## Why have 3 different types of strings and not just quoted strings like in JSON?

There are a few reasons for this:

* In many simple cases bare strings are all you really need. If your keys and values don't have any special characters (like punctuation) then quoting all of them seems silly.
* Double quotes _are_ useful to show the boundaries of a key or a value that really _should_ contain spaces or special characters. No need to completely throw double quotes away.
* Raw strings are really nice for large multi-line string values (like dialog sequences in a game, for example).

## Why only strings and not numbers or Booleans?

TL;DR - Your values are strings to begin with...you can interpret them however your program needs them.

Your program is going to read in all values for any generic data file (such as JSON) as a string. With those strings, you must parse them to interpret them the way to expect (e.g., as numbers or Booleans or strings or whatever). Even if you use a library for this (which you most certainly probably do) the library has to do that same thing.

I think it should be up to the user how their value strings are interpreted. If you're expecting a particular value to be a number, then use your programming language's string parsing utilities to parse it as a number, for example.

Additionally, this takes the burden of ensuring standardized number and boolean formats off of the ZOMB library implementations.

## Why are commas optional instead of either being required in some cases or being removed entirely?

Commas are optional because in _most_ cases they don't really contribute to anything useful.

```zomb
// the commas here don't help anything
key = {
    a = 1,
    b = 2,
    c = 3,
}
```

```zomb
// this is perfectly clear without commas
ports = [ 8000 9000 10000 ]
```

However, they are useful in a few cases (especially when many things are on a single line).

```zomb
$macro(a, b, c = 4) = [ %a %b %c ]
key = macro(hello, goodbye, 5)
```

```zomb
key = { a = 1, b = 2, c = 3 }
```

Ultimately, commas are purely for human readability _in single line_ cases like above. It's just as easy to parse a ZOMB file with or without commas as separators. So, instead of requiring them in only a few cases or eliminating them entirely, they're optional. Use them when you need it for readability and ignore them otherwise.

---

_This work is covered under the MIT License. See LICENSE.md._
