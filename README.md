# The ZOMB file format (WORK IN PROGRESS)

Welcome! This is the `.zomb` data-exchange file format. It's like JSON but with macros (and some other relaxed syntax)!

> _Similar to how JSON is pronounced "j-son", ZOMB is pronounced "zom-b"._

## Key-Value Pairs

```
name = ZOMB

person = {
    name = ZOMB
    job = Hacker
}

"people jobs" = [ Hacker Dishwasher "Dog Walker" ]
```

ZOMB files contain one or more key-value pairs. A key-value pair has a string as the key, followed by an equals sign (`=`), followed by a string, an object, or an array. Let's talk more about each of these value types individually.

**Bare Strings**

A bare string is any set of non-control (0x20 - 0x10FFF) Unicode code points except for the following delimiters:
- White Space
    - Horizontal Tab
    - Linefeed
    - Carriage Return
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

**Quoted Strings**

If you want to include any of the delimiters not allowed in bare strings, then you must surround the string with quotation marks -- standard escape sequences apply. Keys (since they're strings too) may also be quoted.

**Objects**

Objects can hold a set of key-value pairs, just like in JSON:

```
person = {
    name = ZOMB
    job = Hacker
}
```

**Arrays**

Arrays can hold a set of values, just like in JSON:

```
"people jobs" = [
    Hacker
    Dishwasher
    "Dog Walker"
]
```

## Some Little Extras

Let's go over some other fun features of ZOMB file.

**Commas**

From the examples you've seen to this point, no commas were used to separate anything -- _because you don't have to_. If you prefer to use commas (which are indeed helpful delimiters in many cases), you may use a **single** comma between key-value pairs in an object or between values in an array (or between parameters in macros -- we'll get to that in a second).

**White Space**

In general, white space is ignored, except to separate entities and to separate lines in multi-line strings ("Wait, what? Multi-line strings?"). So you can have this if you wanted to:

```
name=ZOMB person={name=ZOMB job=Hacker}"people jobs"=[Hacker Dishwasher "Dog Walker"]
```

**Multi-Line Strings**

For fun, let's describe these in an example:

```
dialog = \\This is a multi-line string.
         \\Newline characters (\n and \r\n) are included in this string
         \\except for the last very last one. The following
         \\is a list of characters you need to escape in these kinds of strings:
         \\  - nothing, because these are also raw strings ;)
```

**Comments**

You can have comments in ZOMB files like this:

```
// this is a comment on its own line

hello = goodbye // this is a comment at the end of a line

// '//' is allowed inside a string and won't be parsed as a comment
// so this  ┌──────────────────────────┐ is not a comment
url = https://github.com/zooce/zomb-file // but this is
```

## Macros

Macros are the special sauce of ZOMB files. They allow you to write reusable values, objects, and arrays. Let's see an example:

```
$jobs = [
    Hacker
    Dishwasher
    "Dog Walker"
]

$person(name, job) = {  // sometimes commas are nice (still not required though)
    name = %name
    job = %job
}

$names = {
    god = Thor
    file = ZOMB
    "the best" = "Chuck Norris"
}

people = [
    $person($names.file, $jobs.0)
    $person($names.god, $jobs.1)
    $person($names."the best", $jobs.2)
    $person(Zooce "Software Engineer")
]
```

There's a lot going on here, but I bet you already kind of get it.

**Defining a Macro**

Macros are defined just like key-value pairs, but with some special rules.

1. Macro keys must start with a dollar sign (`$`).
2. Macros can have a set of parameters (regardless of their value type). Parameters are defined as a list of strings inside a set of parenthesis, after the macro key but before the equals sign.
3. Parameters can be used inside the macro's value by placing a percent sign (`%`) before the parameter name. This eliminates the need for scoping rules.
4. If your macro does have parameters, you must each parameter at least once in the macro's value. This is to keep you from doing unnecessary things.
4. Recursion in macro definitions is forbidden.
    ```
    $name = $name  // not cool

    $macro1(p1 p2) = {
        this = %p1
        that = $macro2(%p2) // this uses `$macro1` -- forbidden
    }

    $macro2(a) = $macro1(a, 5)

    $okay(param) = [ 1 2 %param 3 ]
    // this _is_ okay, because it is not recursion
    my_key = $okay($okay(4))
    ```

**Using a Macro**

To use a macro as a value, you specify its key (including the `$`).

```
$name = Gene

names = [
    Fred
    Kara
    $name  // easy
    Tommy
]
```

If the macro has parameters, you pass them just like you would to a function (in common languages, that is).

```
$person(name, job) = {
    name = %name
    job = %job
}

"cool person" = $person(Zooce, Dishwasher)
```

## And that's it!

So, what do you think? Like it? Hate it? Either way, I hope you at least enjoyed learning about this little file format, and I thank you for taking the time!

---

_This work is covered under the MIT (Expat) License. See LICENSE.md._
