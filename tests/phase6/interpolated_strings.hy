public class Program {
    private static int calls;
    private static int Next() { calls = calls + 1; return calls; }

    public static int Main() {
        string word = null;
        string text = $"n={Next()}, math={2 * 3}, flag={true}, braces={{ok}}, quote=\"é\"";
        if (text != "n=1, math=6, flag=true, braces={ok}, quote=\"é\"" || calls != 1) { return 11; }
        string fallback = $"{word ?? "safe"}";
        if (fallback != "safe") { return 12; }
        string selected = $"{calls == 1 ? "yes" : "no"}";
        if (selected != "yes") { return 13; }
        string empty = $"";
        if (empty != "") { return 14; }
        string utf8 = $"é";
        if (utf8.Length != 2 || System.Console.Utf8ByteAt(utf8, 0) != 195 ||
            System.Console.Utf8ByteAt(utf8, 1) != 169) { return 15; }
        if ($"line\n{2}\tend" != "line\n2\tend") { return 16; }
        return 42;
    }
}
