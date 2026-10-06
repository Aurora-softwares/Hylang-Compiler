public class Program {
    public static void Main(string[] args) {
        System.Console.WriteLine("[KERNEL] Capturing UEFI memory map.");
        System.Console.WriteLine("[KERNEL] Leaving UEFI boot services.");
        System.Uefi.ExitBootServices();
        System.Kernel.MemoryMap.Initialize();
        System.Kernel.Memory.Initialize();
        System.Kernel.VirtualMemory.Initialize();
        System.Kernel.Halt();
    }
}
