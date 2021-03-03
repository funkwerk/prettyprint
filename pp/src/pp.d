module pp;

import std.algorithm;
import std.range;
import std.stdio;
import prettyprint;

void main(string[] args)
{
    const columns = terminalColumns;

    args = args.dropOne; // current executable

    void processLines(T)(T lines)
    {
        lines.each!((const(char)[] line) {
            writeln(prettyprint.prettyprint(cast(string) line, columns));
        });
    }

    if (args.empty)
    {
        processLines(stdin.byLine);
    }
    else
    {
        // like cat
        args.each!(arg => processLines(File(arg).byLine));
    }
}

private int terminalColumns()
{
    import core.sys.posix.fcntl : O_RDONLY, open;
    import core.sys.posix.unistd : close;

    // determine terminal window size even if we're piped
    int tty_fd = open("/dev/tty", O_RDONLY);
    winsize w = winsize.init;

    ioctl((tty_fd != -1) ? tty_fd : 1, TIOCGWINSZ, &w);
    close(tty_fd);

    return w.ws_col ? w.ws_col : 80;
}

private extern(C) int ioctl(int, uint, ...);

private struct winsize
{
    ushort ws_row, ws_col;
    ushort ws_xpixel, ws_ypixel;
}

private enum TIOCGWINSZ = 0x5413;
