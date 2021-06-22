# The ZOMB file format **(!!! WORK IN PROGRESS !!!)**

Welcome to the ZOMB file format specification. It's basically a mix of JSON and TOML...but with macros!

> _NOTE: Similar to how JSON is pronounced "J-son", ZOMB is pronounced "zom-B" 🧟._

## Why use a ZOMB file?

1. No more unwieldy repetition
2. Simple, intuitive rules
3. Easy conversion to other popular file formats

## General Rules and Definitions

- ZOMB files are UTF-8 encoded text files
- "Whitespace" is defined as a tab (U+0009) or a space (U+0020)
- "Newline" is defined as an LF (U+000A) or a CRLF (U+000D U+000A)
- Whitespace and newlines are ignored unless stated otherwise
- Commas as separators are optional - see [Commas](#commas)

## Key-Value Pairs

```zomb
key = value
```

A key-value pair associates a key (which is a string) with a value.

> _NOTE: Keys at the same level, must be unique._

> _NOTE: Using `=` as the separator is taken from the [TOML](https://toml.io/en/) file format._


### Value Types

There are only four types of values:

- [String](#strings)
- [Object](#objects)
- [Array](#arrays)
- [Macro Expression](#using-a-macro) (see the [Macros](#macros) section first)

## Strings

Strings can be simple and yet they have plenty of complicated scenarios. To deal with this conundrum, there are three forms a string can take:

- [Bare String](#bare-strings): A string containing no special delimiters
- [Quoted String](#quoted-strings): A string that may contain special delimiters and escape sequences
- [Raw String](#raw-strings): A string that may contain any characters with no restrictions

### Bare Strings

```zomb
key = a_bare_string
```

```zomb
key = not a bare string  // this is an error!
```

A bare string may contain any Unicode code point except any of these special delimiters:
- Unicode control characters U+0000 through U+001F (includes tab, LF, and CRLF)
- Space (` `)
- Object/Array Delimiters (`{` and `}`)
- Equals Sign (`=`)
- Macro Delimiters (`$`, `%`, `.`, `(`, and `)`)
- Others (`"`, `,`, and `\`)

### Quoted Strings

```zomb
key = "a_quoted_string"  // this is fine, but unnecessary
```

```zomb
key = "a quoted string"
```

```zomb
"this is okay too" = value
```

If you want to include any of the special delimiters not allowed in bare strings, excluding newlines, then you can surround the string with quotation marks -- standard escape sequences apply. Keys (since they're strings too) may also be quoted.

> _The quotation marks (`"`) are only delimiters and are not part of the string's actual value._

### Raw Strings

For fun, let's describe these in a couple of examples:

```zomb
dialog = \\This is a raw string. Raw strings start with '\\' and run to the end
         \\of the line. They continue until either an empty line or another
         \\token is encountered.
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

### Objects

```zomb
file = {
    type = ZOMB
    path = "/home/zooce/passwords.zomb"  // DON'T STORE YOUR PASSWORDS LIKE THIS!
}
```

Objects can hold a set of [key-value](#key-value-pairs) pairs.

> _NOTE: Keys in the same object, must be unique._

### Arrays

```zomb
"people jobs" = [
    Hacker
    Dishwasher
    "Dog Walker"
]
```

Arrays can hold a set of [values](#value-types).

## Macros

Macros are the special sauce of ZOMB files. They allow you to write reusable values, objects, and arrays. Let's see an example:

```zomb
$chuck = "Chuck Norris"
$jobs = [ Hacker Dishwasher "Dog Walker" ]
$names = {
    god = Thor
    file = ZOMB
    "the best" = $chuck
}
$person(name, job) = {  // sometimes commas are nice (still not required though)
    name = %name
    job = %job
}

people = [
    $person($names.file, $jobs.0)
    $person($names.god, $jobs.1)
    $person($names."the best", $jobs.2)
    $person(Zooce "Software Engineer")
]
```

There's a lot going on there, but I bet you already kind of get it, don't you?

### Defining a Macro

Macros are defined just like key-value pairs, but with some special rules.

1. Macro keys must start with a dollar sign (`$`).
2. Macros can have a set of parameters (regardless of their value type). Parameters are defined as a list of strings inside a set of parentheses, placed between the macro key and the equals sign. _An empty set of parentheses is **invalid**._
3. Parameters can be used as values inside the macro's value by placing a percent sign (`%`) before the parameter name. This eliminates the need for complicated scoping rules.
4. If your macro does have parameters, each parameter _must_ be used at least once in the macro's value. This is to keep you from doing unnecessary things.
4. Recursion in macro definitions is forbidden. Here are a couple of examples:
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

### Using a Macro

To use a macro as a value (called a "Macro Expression"), you specify its key (including the `$`).

```zomb
$name = Gene

names = [
    Fred
    Kara
    $name  // easy
    Tommy
]
```

If the macro has parameters, you pass in a value for each. Parameter values can be any type.

```zomb
$person(name, job) = {
    name = %name
    job = %job
}

"cool person" = $person(Zooce, { type = Dishwasher, pay = 100000 })
```

If the macro's value is an object or an array, you can access individual keys or indexes (and even the keys or indexes of nested objects and arrays) with the macro expression followed by a `.` and then either the key or index you want to access.

> _NOTE: You may **NOT** access individual keys or indexes of parameters. Why? Because you pass them in when using a macro expression, so it's unnecessary._

```zomb
$person(name, job) = {
    name = %name
    job = {
        title = %job
        pay = "1,000,000"
        coworkers = [
            Lindsay
            Kai
            Penny
            Kara
        ]
    }
}

last_coworker = $person(Zooce Dishwasher).job.coworkers.3
```

## Comments

You've already seen comments in the previous examples, but now you know that comments are a real thing!

```zomb
// this is a comment on its own line

hello = goodbye // this is a comment at the end of a line

key = [ // comments can be pretty much anywhere
    1 2 3
]
```

Comments start with `//` and run to the end of the line.

## And that's it!

So, what do you think? Like it? Hate it? Either way, I hope you at least enjoyed learning about this little file format, and I appreciate you taking the time!

# Ideas currently being considered

The following are a set of ideas that are actively being considered and may be useful features to add. These are features that I have not fully thought through yet -- e.g., "Is this feature easy to understand?" "Is this feature difficult to implement?" "Is this feature worth the complexity it costs?".

## String Concatenation

I'm thinking it might be useful to allow string concatenation.

```zomb
$greet(name) = "Hello, " ++ %name

greetings [
    $greet(Zooce)
    $greet(Lindz)
]
```

> _Using `++` as the delimiter is taken from [Zig](https://ziglang.org)._

## Default Macro Parameter Values

It might be nice to have the ability to set default macro parameter values like this:

```zomb
$item(id, label = null) = {
    id = %id
    label = %label
}

item_1 = $item(Hello)
item_2 = $item(Hello, "What's up?")
```

## Boolean and Empty Value Types

It may be argued that these types are so common, that they should be part of the specification.

The main reason I _don't_ like this is that they require a specific keyword, which means if you want the value as a string, you have to quote it (e.g., `false` vs `"false"`). That's obviously fine, but that's just one more rule to add about strings, which are already complicated enough.

**An alternative to consider:**

ZOMB parsing libraries can provide a configuration API for user defined keyword-type mappings or maybe a set of convenience functions for interpreting a string value as some other type (integers, floats, boolean, null, etc.). For example, the user might want `0` and `1` to be interpreted as boolean types, and `_` to be a null type:

```zomb
pin0 = 1  // true
pin1 = 0  // false
pin2 = 1  // true

rw = _  // null
```

---

_This work is covered under the MIT License. See LICENSE.md._
