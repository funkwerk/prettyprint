module prettyprint;

@safe:

import std.algorithm;
import std.range;
import std.typecons;
version(unittest) import unit_threaded.should;

/**
 * This function takes the input text and returns a pretty-printed, multiline, indented version.
 * It assumes that the input text is the output of a well-structured toString and forms a valid
 * comma separated paren tree.
 *
 * A comma separated paren tree is a string that contains a balanced number of quotation marks, parentheses
 * and brackets.
 *
 * For example, the string may take the form `Class(field1=1, field2="text", field3=Struct(a=4, b=5))`.
 */
public string prettyprint(const string text, size_t columnWidth = 80)
{
    const trees = text.parse;

    if (trees.empty)
    {
        return text;
    }

    auto buffer = OutputBuffer();

    trees.each!(tree => prettyprint(buffer, tree, columnWidth));
    return buffer.data;
}

///
@("pretty print a string")
unittest
{
    import std.string : outdent, strip;

    prettyprint("Foo").shouldEqual("Foo");
    prettyprint("Foo(").shouldEqual("Foo(");
    prettyprint("Foo()").shouldEqual("Foo()");
    prettyprint("Foo[]").shouldEqual("Foo[]");
    prettyprint("Foo{}").shouldEqual("Foo{}");
    prettyprint("Foo(A, B)").shouldEqual("Foo(A, B)");
    prettyprint("Foo(Bar(Baz()), Baq())", 16).shouldEqual("
        Foo(
            Bar(Baz()),
            Baq()
        )".outdent.strip);
    prettyprint("Foo(Bar(Baz()), Baq())", 12).shouldEqual("
        Foo(
            Bar(
                Baz(
                )
            ),
            Baq()
        )".outdent.strip);
}

@("list of strings")
unittest
{
    prettyprint(`["a", "b"]`).shouldEqual(`["a", "b"]`);
}

// bug
@("linebreak with comma separated elements without children")
unittest
{
    import std.string : outdent, strip;

    const filler = "-".repeat(80).join;

    prettyprint(filler ~ `("a", "b")`).shouldEqual(filler ~ `
    (
        "a",
        "b"
    )`.outdent.strip);
}

private enum indent = " ".repeat(4).join;

private void prettyprint(ref OutputBuffer buffer, const Tree tree, size_t width)
{
    import std.string : stripLeft;

    // skip prefix so caller can decide whether or not to strip
    void renderSingleLine(const Tree tree) @safe
    {
        if (tree.parenType.isNull)
        {
            buffer ~= tree.suffix;
            return;
        }
        buffer ~= tree.parenType.get.opening;
        tree.children.enumerate.each!((index, child) {
            buffer ~= child.prefix;
            renderSingleLine(child);
        });
        buffer ~= tree.parenType.get.closing;
        buffer ~= tree.suffix;
    }

    void renderIndented(const Tree tree, size_t level = 0) @safe
    {
        const remainingWidth = width - buffer.currentLineLength;

        buffer ~= (level == 0) ? tree.prefix : tree.prefix.stripLeft;
        if (!tree.lengthExceeds(remainingWidth))
        {
            renderSingleLine(tree);
            return;
        }
        if (tree.parenType.isNull)
        {
            buffer ~= tree.suffix;
            return;
        }
        buffer ~= tree.parenType.get.opening;
        tree.children.enumerate.each!((index, child) {
            buffer.newline;
            (level + 1).iota.each!((_) { buffer ~= indent; });
            renderIndented(child, level + 1);
        });
        buffer.newline;
        level.iota.each!((_) { buffer ~= indent; });
        buffer ~= tree.parenType.get.closing;
        buffer ~= tree.suffix;
    }
    renderIndented(tree);
}

private struct OutputBuffer
{
    Appender!string appender;

    size_t lastLinebreak = 0;

    void opOpAssign(string op, T)(T text)
    if (op == "~")
    {
        this.appender ~= text;
    }

    string data()
    {
        return this.appender.data;
    }

    size_t currentLineLength()
    {
        return this.appender.data.length - this.lastLinebreak;
    }

    void newline()
    {
        this.appender ~= "\n";
        this.lastLinebreak = this.appender.data.length;
    }
}

private Tree[] parse(string text)
{
    auto textRange = text.quoted;
    Tree[] trees;

    do
    {
        auto tree = textRange.parse;

        if (tree.isNull)
        {
            return null;
        }

        trees ~= tree.get;
    }
    while (!textRange.empty);

    return trees;
}

@("parse a paren expression to a tree")
unittest
{
    parse("Foo").shouldEqual([Tree("Foo")]);
    parse(`"Foo"`).shouldEqual([Tree(`"Foo"`)]);
    parse("Foo,").shouldEqual([Tree("Foo", Nullable!ParenType(), null, ",")]);
    parse("Foo, Bar").shouldEqual([
        Tree("Foo", Nullable!ParenType(), null, ","),
        Tree(" Bar")]);
    parse("Foo()").shouldEqual([Tree("Foo", ParenType.paren.nullable)]);
    parse("Foo[a, b]").shouldEqual([Tree(
        "Foo",
        ParenType.squareBracket.nullable,
        [Tree("a", Nullable!ParenType(), null, ","), Tree(" b")])]);
    parse(`Foo{"\""}`).shouldEqual([Tree(
        "Foo",
        ParenType.curlyBracket.nullable,
        [Tree(`"\""`)])]);
    parse("Foo{`\"`}").shouldEqual([Tree(
        "Foo",
        ParenType.curlyBracket.nullable,
        [Tree("`\"`")])]);
    parse("Foo{'\"'}").shouldEqual([Tree(
        "Foo",
        ParenType.curlyBracket.nullable,
        [Tree("'\"'")])]);
    parse("Foo() Bar()").shouldEqual([
        Tree("Foo", ParenType.paren.nullable),
        Tree(" Bar", ParenType.paren.nullable)]);
}

// bug
@("tree with trailing text")
unittest
{
    parse(`(() )`).shouldEqual([
        Tree(
            "",
            ParenType.paren.nullable,
            [
                Tree("", ParenType.paren.nullable),
                Tree(" "),
            ])]);
}

// bug
@("quote followed by wrong closing paren")
unittest
{
    const text = `("",""]`;

    parse(text).shouldEqual(Tree[].init);
}

// bug
@("list of strings")
unittest
{
    parse(`["a", "b"]`).shouldEqual([Tree("", ParenType.squareBracket.nullable, [
        Tree(`"a"`, Nullable!ParenType(), null, ","),
        Tree(` "b"`),
    ])]);
}

private Nullable!Tree parse(ref QuotedText textRange, string expectedClosers = ",")
{
    auto parenStart = textRange.findAmong("({[");
    auto closer = textRange.findAmong(expectedClosers);

    if (textRange.textUntil(closer).length < textRange.textUntil(parenStart).length)
    {
        const prefix = textRange.textUntil(closer);

        textRange = closer.consumeQuote;

        return prefix.empty ? Nullable!Tree() : textRange.parseSuffix(Tree(prefix)).nullable;
    }

    const prefix = textRange.textUntil(parenStart);

    if (parenStart.empty)
    {
        textRange = parenStart.consumeQuote;

        return prefix.empty ? Nullable!Tree() : textRange.parseSuffix(Tree(prefix)).nullable;
    }

    const parenType = () {
        switch (parenStart.front)
        {
            case '(':
                return ParenType.paren;
            case '[':
                return ParenType.squareBracket;
            case '{':
                return ParenType.curlyBracket;
            default:
                assert(false);
        }
    }();

    textRange = parenStart;
    textRange.popFront;

    Tree[] children = null;

    while (true)
    {
        if (textRange.empty)
        {
            return Nullable!Tree();
        }
        if (textRange.front == parenType.closing)
        {
            // single child, quote only
            const quoteChild = textRange.textUntil(textRange);

            if (!quoteChild.empty)
            {
                children ~= Tree(quoteChild);
            }

            textRange.popFront;

            return textRange.parseSuffix(Tree(prefix, Nullable!ParenType(parenType), children)).nullable;
        }

        auto child = textRange.parse(parenType.closingWithComma);

        if (child.isNull)
        {
            return Nullable!Tree();
        }

        children ~= child;
    }
}

private Tree parseSuffix(ref QuotedText range, Tree tree)
in (tree.suffix.empty)
{
    if (!range.empty && range.front == ',')
    {
        range.popFront;
        tree.suffix = ",";
    }
    return tree;
}

// prefix
// prefix { (child(, child)*)? }
// prefix ( (child(, child)*)? )
// prefix [ (child(, child)*)? ]
private struct Tree
{
    string prefix;

    Nullable!ParenType parenType = Nullable!ParenType();

    Tree[] children = null;

    string suffix = null;

    bool lengthExceeds(size_t limit) const
    {
        return lengthRemainsOf(limit) < 0;
    }

    // returns how much remains of length after printing this. if negative, may be inaccurate.
    private ptrdiff_t lengthRemainsOf(ptrdiff_t length) const
    {
        length -= this.prefix.length;
        length -= this.suffix.length;
        length -= this.parenType.isNull ? 0 : 2;
        if (length >= 0)
        {
            foreach (child; this.children)
            {
                length = child.lengthRemainsOf(length);
                if (length < 0)
                {
                    break;
                }
            }
        }
        return length;
    }
}

@("estimate the print length of a tree")
unittest
{
    parse("Foo(Bar(Baz()), Baq())").front.lengthRemainsOf(10).shouldBeSmallerThan(0);
}

private enum ParenType
{
    paren, // ()
    squareBracket, // []
    curlyBracket, // {}
}

private alias opening = mapEnum!([
    ParenType.paren: '(',
    ParenType.squareBracket: '[',
    ParenType.curlyBracket: '{']);

private alias closing = mapEnum!([
    ParenType.paren: ')',
    ParenType.squareBracket: ']',
    ParenType.curlyBracket: '}']);

private alias closingWithComma = mapEnum!([
    ParenType.paren: ",)",
    ParenType.squareBracket: ",]",
    ParenType.curlyBracket: ",}"]);

private auto mapEnum(alias enumTable)(const typeof(enumTable.keys.front) key)
{
    final switch (key)
    {
        static foreach (mapKey, mapValue; enumTable)
        {
            case mapKey:
                return mapValue;
        }
    }
}

private QuotedText quoted(string text)
{
    return QuotedText(text);
}

// range over text that skips quoted strings
private struct QuotedText
{
    string text; // current read head after skipping quotes

    string textBeforeSkip; // current read head before skipping quotes

    debug invariant(this.text.refSuffixOf(this.textBeforeSkip));

    this(string text)
    {
        this(text, text);
    }

    private this(string text, string textBeforeSkip)
    {
        this.text = text;
        this.textBeforeSkip = textBeforeSkip;
        skipQuote;
    }

    QuotedText consumeQuote()
    {
        // set this.textBeforeSkip to this.text, indicating that we've already accounted for quotes
        return QuotedText(this.text);
    }

    // return text from start until other, which must be a different range over the same text
    string textUntil(QuotedText other)
    in (other.text.refSuffixOf(this.textBeforeSkip))
    {
        // from our skip-front to other's skip-back
        // ie. foo"test"bar
        // from   ^ to ^ is the "same" range, but returns '"test"'
        return this.textBeforeSkip[0 .. this.textBeforeSkip.length - other.text.length];
    }

    bool empty() const
    {
        return this.text.empty;
    }

    dchar front() const
    {
        return this.text.front;
    }

    void popFront()
    {
        this.text.popFront;
        this.textBeforeSkip = this.text;
        skipQuote;
    }

    private void skipQuote()
    {
        bool skippedQuote(dchar marker, bool escapeChars)
        {
            if (this.text.empty || this.text.front != marker)
            {
                return false;
            }
            this.text.popFront; // skip opening marker character

            while (!this.text.empty && this.text.front != marker)
            {
                if (escapeChars && this.text.front == '\\')
                {
                    this.text.popFront; // if escaping, skip an additional character
                }
                if (!this.text.empty)
                {
                    this.text.popFront;
                }
            }
            if (!this.text.empty)
            {
                this.text.popFront; // skip closing marker
            }
            return true;
        }

        while (skippedQuote('"', true) || skippedQuote('\'', true) || skippedQuote('`', false))
        {
        }
    }
}

// given an unsigned offset, left can be written as right[offset .. $].
private bool refSuffixOf(string left, string right)
{
    return cast(size_t) left.ptr + left.length == cast(size_t) right.ptr + right.length && left.ptr >= right.ptr;
}

@("\"\" quote at the beginning and end of a range")
unittest
{
    auto range = QuotedText(`"Foo"`);

    range.textUntil(range).shouldEqual(`"Foo"`);
}

@("`` quote at the beginning and end of a range")
unittest
{
    auto range = QuotedText("`Foo\\`");

    range.textUntil(range).shouldEqual("`Foo\\`");
}

@("'' quote at the beginning and end of a range")
unittest
{
    auto range = QuotedText("'Foo'");

    range.textUntil(range).shouldEqual("'Foo'");
}
