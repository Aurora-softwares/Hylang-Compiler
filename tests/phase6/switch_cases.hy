public class Program {
    private static int calls;
    private static int Next() { calls = calls + 1; return calls; }

    public static int Main() {
        int total = 0;
        switch (Next()) {
            case 1: total = total + 10; break;
            case 2: total = total + 20; break;
            default: total = total + 30;
        }
        if (total != 10 || calls != 1) { return 11; }

        int selected = switch (Next()) {
            case 1 => 4,
            case 2 => 20,
            default => 0
        };
        if (selected != 20 || calls != 2) { return 12; }

        bool flag = true;
        string word = switch (flag) {
            case true => "yes",
            case false => "no"
        };
        if (word != "yes") { return 13; }

        switch ("red") {
            case "blue": return 14;
            case "red": total = total + 12; break;
            default: return 15;
        }
        if (total != 22) { return 16; }
        int other = switch (7) { case 1 => 1, default => 7 };
        string color = switch ("blue") { case "red" => "R", default => "B" };
        if (other != 7 || color != "B") { return 17; }
        int nested = 0;
        switch (1) {
            case 1:
                while (nested < 3) { nested = nested + 1; if (nested < 3) { continue; } }
                break;
        }
        if (nested != 3) { return 18; }
        return 42;
    }
}
