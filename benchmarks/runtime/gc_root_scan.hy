// Vary stack depth without varying managed heap size. Subtract the matching
// skip run to estimate the extra collection work from scanning stack roots.
public class Program {
    private static int Dive(int depth, int collect) {
        int marker = depth;
        if (depth == 0) {
            if (collect == 1) { System.Runtime.GC.Collect(); }
            return marker;
        }
        int result = Dive(depth - 1, collect);
        return result + marker - marker;
    }

    public static int Main(string[] args) {
        int depth = System.Convert.ToInt32(args[0]);
        int collect = System.Convert.ToInt32(args[1]);
        if (depth < 0 || depth > 50000 || collect < 0 || collect > 1) { return 2; }
        System.Console.WriteLine(Dive(depth, collect));
        return 0;
    }
}
