public class Program {
    public static void Main(string[] args) {
        System.Console.WriteLine("[BOOT] Loading EFI kernel...");
        System.Uefi.StartImage("\\EFI\\AUSTRALIS\\KERNEL.EFI");
    }
}
