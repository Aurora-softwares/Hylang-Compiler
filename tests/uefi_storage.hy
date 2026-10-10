public class Program {
    public static void Main(string[] args) {
        System.Console.WriteLine("[KERNEL] Preparing live AHCI storage.");
        System.Uefi.ExitBootServices();
        System.Kernel.MemoryMap.Initialize();
        System.Kernel.Memory.Initialize();
        System.Kernel.VirtualMemory.Initialize();
        System.Kernel.VirtualMemory.ApplyPolicy();
        System.Kernel.Heap.Initialize();
        System.Kernel.Framebuffer.Initialize();
        System.Kernel.Gdt.Initialize();
        System.Kernel.Idt.Initialize();
        System.Kernel.Interrupts.Initialize();
        System.Kernel.Timer.Initialize();
        System.Kernel.Pci.Initialize();
        System.Kernel.Mmio.Initialize();
        System.Kernel.Dma.Initialize();
        System.Kernel.Dma.AllocatePages(16);
        System.Kernel.Storage.Initialize();
        System.Kernel.Interrupts.Enable();
        System.Kernel.Interrupts.Idle();
    }
}
