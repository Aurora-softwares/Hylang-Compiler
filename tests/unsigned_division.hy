public class Program {
    public static void Main() {
        ulong maximum = (ulong)(-1);
        if (maximum / (ulong)3 != 6148914691236517205 || maximum % (ulong)3 != 0) {
            System.Console.WriteLine("bad-ulong");
            return;
        }
        uint wide = (uint)(-1);
        if (wide / (uint)3 != 1431655765 || wide % (uint)3 != 0) {
            System.Console.WriteLine("bad-uint");
            return;
        }
        System.Console.WriteLine("unsigned-division-ok");
    }
}
