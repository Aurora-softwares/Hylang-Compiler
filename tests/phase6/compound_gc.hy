public class Program {
    private static int[] FreshPages() {
        int[] pages = new int[2048];
        pages[1500] = 1;
        return pages;
    }
    private static int CollectValue() { System.Runtime.GC.Collect(); return 77; }

    public static int Main() {
        int collected = (FreshPages()[1500] += CollectValue());
        if (collected != 78) { return 11; }
        return 42;
    }
}
