public class Program {
    public static void Main(string[] args) {
        System.Uefi.ClearScreen();
        System.Console.WriteLine("[BOOT] Press a key to continue.");
        System.Uefi.Await();
        System.Uefi.StartImage("\\EFI\\AUSTRALIS\\KERNEL.EFI");
    }
}
