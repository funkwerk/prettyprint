# prettyprint

prettyprint takes a string representing a tree of parentheses and linebreaks and indents it.

# Usage

## Command line tool

    dub run prettyprint < logfile

## Library

```
import prettyprint : prettyprint;

string formattedOutput = object.toString().prettyprint;
```

# API

    public string prettyprint(const string text, size_t columnWidth = 80);
