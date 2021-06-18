# The ZOMB file format (WORK IN PROGRESS)

Welcome! This is the ZOMB data-exchange file format. It's like JSON but with macros (and some other relaxed syntax)!

> _Similar to how JSON is pronounced "j-son", ZOMB is pronounced "zom-b"._

## Objectives

There are three main objectives of the ZOMB file format:

1. Eliminate unwieldy repetition
2. Flexible (but reasonable) formatting
3. As few complicated rules as possible

## General Rules and Definitions

- ZOMB files must be UTF-8 encoded
- "Whitespace" is defined as a tab (U+0009) or a space (U+0020)
- "Newline" is defined as an LF (U+000A) or CRLF (U+000D U+000A)
- Whitespace and newlines are ignored unless stated otherwise
- Commas as separators are optional - see [Commas](#commas)

## Key-Value Pairs

```
key = value
```

ZOMB files contain one or more key-value pairs. A key-value pair has a string as the key, followed by an equals sign (`=`), followed by a value.

> _NOTE: Keys at the same level, must be unique._

There are only four types of values:

- [String](#strings)
- [Object](#objects)
- [Array](#arrays)
- [Macro Expression](#using-a-macro) (see the [Macros](#macros) section first)

## Strings

Strings are simple and yet complicated at the same time. To deal with this conundrum, there are three forms a string can take:

- [Bare String](#bare-strings): A string containing no special delimiters
- [Quoted String](#quoted-strings): A string that may contain special delimiters and escape sequences
- [Raw String](#raw-strings): A string that may contain any characters with no restrictions

### Bare Strings

```
key = a_bare_string
```

```
key = not a bare string  // this is an error!
```

A bare string may contain any Unicode code point except the following:
- Unicode control characters U+0000 through U+001F (includes tab, LF, and CRLF)
- Space
- Object/Array Delimiters
    - Open/Close Curly Braces
    - Open/Close Square Brackets
- Equals Sign
- Macro Delimiters
    - Dollar Sign
    - Percent Sign
    - Full Stop (Period/Dot)
    - Open/Close Parenthesis
- Others:
    - Quotation Mark (Double Quotes)
    - Comma
    - Reverse Solidus (Back Slash)

### Quoted Strings

```
key = "a_quoted_string"  // this is fine, but it doesn't really need to be quoted
```

```
key = "a quoted string"
```

```
"this is okay too" = value
```

If you want to include any of the delimiters not allowed in bare strings, excluding newlines, then you must surround the string with quotation marks -- standard escape sequences apply. Keys (since they're strings too) may also be quoted.

> _The quotation marks (`"`) are only delimiters and are not part of the string's actual value._

### Raw Strings

For fun, let's describe these in a couple of examples:

```
dialog = \\This is a raw string. Raw strings start with '\\' and run to the end
         \\of the line. They continue until either an empty line or another
         \\token is encountered.
         \\
         \\Raw strings may contain any characters without the need to escape
         \\anything.
         \\
         \\Newlines are included in this string except for the last very last
         \\one.
```

```
dialog = \\blah blah
         \\blah blah

         \\this is an ERROR
```

```
\\Raw strings CANNOT
\\be used as keys
= value
```

> _The leading backslashes (`\\`) are only delimiters and are not part of the string's actual value._

> _Using `\\` as the delimiter is taken from the [Zig](https://ziglang.org) programming language._

### Objects

```
file = {
    type = ZOMB
    path = "/home/zooce/passwords.zomb"  // DON'T STORE YOUR PASSWORDS LIKE THIS!
}
```

Objects can hold a set of key-value pairs, just like in JSON.

> _NOTE: Keys in the same object, must be unique._

### Arrays

```
"people jobs" = [
    Hacker
    Dishwasher
    "Dog Walker"
]
```

Arrays can hold a set of values, just like in JSON.

## Macros

Macros are the special sauce of ZOMB files. They allow you to write reusable values, objects, and arrays. Let's see an example:

```
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

There's a lot going on here, but I bet you already kind of get it, don't you?

### Defining a Macro

Macros are defined just like key-value pairs, but with some special rules.

1. Macro keys must start with a dollar sign (`$`).
2. Macros can have a set of parameters (regardless of their value type). Parameters are defined as a list of strings inside a set of parentheses, placed between the macro key and the equals sign. _An empty set of parentheses is **invalid**._
3. Parameters can be used inside the macro's value by placing a percent sign (`%`) before the parameter name. This eliminates the need for complicated scoping rules.
4. If your macro does have parameters, each parameter _must_ be used at least once in the macro's value. This is to keep you from doing unnecessary things.
4. Recursion in macro definitions is forbidden. Here are a couple of examples:
    ```
    $name = $name  // not cool
    ```

    ```
    $macro1(p1 p2) = {
        this = %p1
        that = $macro2(%p2) // this uses `$macro1` -- forbidden
    }
    $macro2(a) = $macro1(a, 5)
    ```

    ```
    $okay(param) = [ 1 2 %param 3 ]

    // this _is_ okay, because it is not recursion
    my_key = $okay($okay(4))
    ```

### Using a Macro

To use a macro as a value (called a "Macro Expression"), you specify its key (including the `$`).

```
$name = Gene

names = [
    Fred
    Kara
    $name  // easy
    Tommy
]
```

If the macro has parameters, you pass them just like you would to a function (in common programming languages, that is).

```
$person(name, job) = {
    name = %name
    job = %job
}

"cool person" = $person(Zooce, Dishwasher)
```

If the macro's value is an object or an array, you can access individual keys or indexes (and even the keys or indexes of nested objects and arrays) with the macro expression followed by a `.` and then either the key or index you want to access.

```
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

```
// this is a comment on its own line

hello = goodbye // this is a comment at the end of a line
```

Comments start with `//` and run to the end of the line.

## And that's it!

So, what do you think? Like it? Hate it? Either way, I hope you at least enjoyed learning about this little file format, and I thank you for taking the time!

# Ideas currently being considered

The following are a set of ideas that are actively being considered and may be useful features to add. These are features that I have not fully thought through yet -- e.g., "Is this feature easy to understand?" "Is this feature difficult to implement?" "Is this feature worth the complexity it costs?".

## String Concatenation

I'm thinking it might be useful to allow string concatenation.

```
$greet(name) = "Hello, " ++ %name

greetings [
    $greet(Zooce)
    $greet(Lindz)
]
```

> _Using `++` as the delimiter is taken from [Zig](https://ziglang.org)._

## Default Macro Parameter Values

It might be nice to have the ability to set default macro parameter values like this:

```
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

ZOMB parsing libraries can provide a configuration API for user defined keyword-type mappings. For example, the user might want `0` and `1` to be interpreted as boolean types, and `_` to be a null type:

```
pin0 = 1  // true
pin1 = 0  // false
pin2 = 1  // true

rw = _  // null
```

---

_This work is covered under the MIT License. See LICENSE.md._
