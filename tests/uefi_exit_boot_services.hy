public class Program {
    public static void Main(string[] args) {
        System.Console.WriteLine("[KERNEL] Capturing UEFI memory map.");
        System.Console.WriteLine("[KERNEL] Leaving UEFI boot services.");
        System.Uefi.ExitBootServices();
        System.Kernel.MemoryMap.Initialize();
        System.Kernel.Memory.Initialize();
        System.Kernel.VirtualMemory.Initialize();
        System.Kernel.VirtualMemory.ApplyPolicy();
        System.Kernel.Memory.AllocatePage();
        System.Kernel.Heap.Initialize();
        System.Kernel.Heap.Allocate(8192);
        System.Kernel.Heap.Allocate(64);
        System.Kernel.Halt();
    }
}
