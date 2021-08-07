# The ZOMB file format

Welcome to the ZOMB file format specification. It's sort of a 90/10 mix of JSON and TOML...plus macros!

> _Similar to how JSON is pronounced "J-son", ZOMB is pronounced "zom-B" 🧟._

## Why use a ZOMB file?

Are your data/config files plagued with unwieldy repetition? Don't like all those double quotes everywhere? Don't want your file format to dictate your value types? Do you wish commas were optional?

If your answer to any of these questions is "yes", then a ZOMB file might be what you're looking for.

## General Rules, Guidelines, and Definitions

- ZOMB files are UTF-8 encoded text files
- ZOMB files typically have a `.zomb` extension
- "Whitespace" is defined as a tab (U+0009) or a space (U+0020)
- "Newline" is defined as an LF (U+000A) or a CRLF (U+000D U+000A)
- Whitespace and newlines are ignored unless stated otherwise
- Commas as separators are optional - see [Commas](#commas)

## Key-Value Pairs

A key-value pair associates a key (which is a string) with a value.

```zomb
key = value
```

> _Keys at the same level, must be unique._

> _Using `=` as the separator is taken from the [TOML](https://toml.io/en/) file format._

### Value Types

There are only four types of values:

- [String](#strings)
- [Object](#objects)
- [Array](#arrays)
- [Macro Expression](#using-a-macro) (see [Macros](#macros))

## Strings

Strings can be simple and yet they have plenty of complicated scenarios. ZOMB files deal with this by placing strings in three categories:

- [Bare String](#bare-strings): A string containing no special delimiters
- [Quoted String](#quoted-strings): A string that may contain special delimiters and escape sequences
- [Raw String](#raw-strings): A string that may contain any characters with no restrictions

### Bare Strings

A bare string may contain any Unicode code point except any of these special delimiters:

- Unicode control characters (U+0000 through U+001F)
- ` `, `,`, `.`, `"`, `\` (U+0020, U+002C, U+002E, U+0022, U+005C)
- `=`, `$`, `%`, `+` (U+003D, U+0024, U+0025, U+002B)
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
         \\Newlines are included in raw strings except for the last very last
         \\one.
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

### Objects

Objects group a set of [key-value](#key-value-pairs) pairs, inside a pair of curly braces.

```zomb
file = {
    type = ZOMB
    path = "/home/zooce/passwords.zomb"  // DON'T STORE YOUR PASSWORDS LIKE THIS!
}
```

```zomb
key = {}  // empty objects are okay
```

> _Keys in the same object, must be unique._

### Arrays

Arrays group a set of [values](#value-types), inside square brackets.

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

## Macros

Macros are the special sauce of ZOMB files. They allow you to write reusable values. Let's see an example:

```zomb
$chuck = "Chuck Norris"
$jobs = [ Hacker Dishwasher "Dog Walker" ]
$names = {
    god = Thor
    file = ZOMB
    "the best" = $chuck
}
// sometimes commas are nice (still not required though)
$person(name, job = "Software Engineer") = {
    name = %name
    job = %job
}

people = [
    $person($names.file, $jobs.0)
    $person($names.god, $jobs.1)
    $person($names."the best", $jobs.2)
    $person(Zooce)
]
```

There's a lot going on there, but I bet you already kind of get it.

Macros are defined just like key-value pairs, but with some special rules.

### Macro Keys

The key for a macro can be either a bare string or a quoted string, with a leading dollar sign (`$`).

```zomb
$macro1 = Hello
$"macro two" = Goodbye
```

### Macro Parameters

Macros can have a set of parameters declared after the key inside a set of parentheses. Parameters can be used as values inside the macro by placing a percent sign (`%`) before the parameter name. If your macro does have parameters, each parameter _must_ be used at least once in the macro's value.

> _An empty set of parentheses is **invalid**._

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

### Using a Macro

To use a macro as a value, called a "Macro Expression", you specify its key (including the `$`).

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

If the macro's value is an object or an array, you can access individual keys or indexes (and even the keys or indexes of nested objects and arrays) by following the macro expression with one or more access patterns like `.key` or `.2` for example.

> _You may **NOT** access individual keys or indexes of parameter values. Why? Because you're the one who passes them in when using a macro expression, so it doesn't really make sense to do that._

```zomb
$person(name, job) = {
    name = %name
    job = {
        title = %job
        pay = "1,000,000"
        coworkers = [
            Lindsay
            Penny
            Kai
            Maeve
            Xena
        ]
    }
}

last_coworker = $person(Zooce Dishwasher).job.coworkers.3
```

### (No) Recursion

Recursion in macro definitions is forbidden.

```zomb
$name = $name  // not cool
```

```zomb
$macro1(p1 p2) = {
    this = %p1
    that = $macro2(%p2) // this uses `$macro1` -- forbidden
}
$macro2(a) = $macro1(a, 5)
```

```zomb
$okay(param) = [ 1 2 %param 3 ]

// this _is_ okay, because it is not recursion
my_key = $okay($okay(4))
```

## Concatenation

ZOMB files allow same-type value concatenation (string-string, object-object, and array-array) with the `+` operator. The following examples are boring, but they get the point across.

```zomb
key = bare_string + "quoted string" + \\raw-
                                      \\string
```

```zomb
key = { a = hello } + { b = world }
```

```zomb
key = [ 1 2 3 ] + [ 4 5 6 ]
```

This feature becomes very useful when macros are involved.

```zomb
$greet(name) = "Hello, " + %name

greetings = [
    $greet(Zooce)
    $greet(Bruno)
    $greet(Kenny)
]
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

## And that's it!

So, what do you think? Like it? Hate it? Either way, I hope you at least enjoyed learning about this little file format. It's useful to me and I certainly hope it's useful for you.

# Current Implementations and Utilities

- [`zomb-zig`](https://github.com/Zooce/zomb-zig): ZOMB reader/writer library
- _planning on a Python implementation soon_
- _planning on a ZOMB to JSON/TOML/YAML utility soon_

> _Hopefully even more coming soon!_

---

_This work is covered under the MIT License. See LICENSE.md._
