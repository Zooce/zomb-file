# The ZOMB file format

Welcome! This is the `.zomb` data-exchange file format. It's like JSON but with macros (and some other relaxed syntax)!

> _Similar to how JSON is pronounced "j-son", ZOMB is pronounced "zom-b"._

## Basics

Here's a basic example (without macros):

```
$m1(one two) = { // macro with paramters
    hello = $one
    goodbye = $two
}
$hi = this // macro without parameters
// Did you notice you can have comments?
cool = {
    ports = [ 800 900 ]
    this = $hi
    "wh.at" = $m1( 0 $m1( a, b ) ).goodbye  // commas are optional, yay!
    // "thing" points to a multi-line string...cool I guess
    oh_yea = { thing = \\cool = {
                       \\    ports = [ 800 900 ]
                       \\    this = $hi
                       \\    what = $m1( 0 $m1( a b ) ).goodbye
                       \\    oh_yea = { thing = "nope" }
                       \\}
                       \\$m1(one two) = {
                       \\    hello = $one
                       \\    goodbye = $two
                       \\}
    }
}
```

A couple things before we see Macros in action.

1. Strings only need to be quoted (with double quotes) if they include any of the file delimiters (e.g. ` `, `.`, `{`, etc.).
2. You don't see any commas in this example, but you can use a single comma to separate entities, just like JSON requires.

## Macros

Macros are the special sauce of Zombie files. They allow you to write reusable values, objects, and arrays. They have _mostly_ the same declaration syntax as any other value, object, or array, except their name (or key) must start with a dollar sign (`$`) and can optionally have a set of parameters.

> _If you're one of those super smart people and already you're thinking about how macros may cause issues (like with recursion), then I'll just tell you now that recursion is forbidden. There's a section on this below -- keep reading._

**Value Macro**

A "Value Macro" is a macro whose value is just string.

```
$light = #f2f2f2
$dark  = #2b2b2b

tokenColors = [
    {
        scope = "comment.line",
        settings = {
            foreground = $dark,
        },
    },
    {
        scope = "comment.line.message",
        settings = {
            foreground = $light,
        },
    },
]
```

**Object Macro**

An "Object Macro" is a macro whose value is an object. You use the entire object as a value or you can access individual keys and use them as values.

```
$settings_obj = {
    foreground = #f2f2f2,
}

tokenColors = [
    {
        scope = "comment.line",
        settings = $settings_obj,  // [1]
    },
    {
        scope = "comment.line.message",
        settings = {
            foreground = $settings.foreground_obj,  // [2]
        },
    },
]
```

**Array Macro**

An "Array Macro" is a macro whose value is an array. You can use the entire array as a value or you can access individual indexes and use them as values.

```
$ports = [ 8000, 8001, 9000 ]

servers = {
    stage = {
        ports = $ports,
    },
    prod = {
        ports = [ $ports.0, $ports.2 ]
    }
}
```

## References to other data-file formats

**Interesting things about [Eno](https://eno-lang.org/guide/)**

- the first character of a line is special
- arrays are interesting:

    instead of `[ a, b, c ]` they have:

    ```
    - a
    - b
    - c
    ```

**[NestedText](https://github.com/KenKundert/nestedtext) has a nice simple format**

---

_This work is covered under the MIT (Expat) License. See LICENSE.md._
