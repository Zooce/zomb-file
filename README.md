# Zombie

Welcome! This is the `Zombie` data-file format. It's like JSON but with macros (and some other relaxed syntax)!

## Basics

Here's a basic example (without macros):

```
"$schema" = vscode://schemas/color-theme
name = "Zooce Dark"
type = Dark
colors = {
    "editor.foreground" = #f2f2f2,
    "editor.background" = #2b2b2b,
}
tokenColors = [
    {
        scope = "punctuation.definition.arguments",
        settings = {
            foreground = #f2f2f2,
        },
    },
    {
        scope = comment,
        settings = {
            foreground = #8a8a8a,
            fontStyle = italic,
        },
    },
]
ports = [ 8000, 9000, 8001 ]
```

A couple things before we see Macros in action.

1. Strings only need to be quoted (with double quotes) if they include any of the file delimiters (e.g. ` `, `.`, `{`, etc.).
2. "Top-level" key-value pair declarations are separated by newlines, not commas.
3. Key-value pairs within an object or values within an array need to be separated by commas. You can also use a trailing comma -- this is nice because next time you want to add a key-value pair or a new value to an array, you don't need to add a comma after the value above it.

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
