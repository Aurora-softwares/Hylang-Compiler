public class Program {
    public static void Main(string[] args) {
        System.Console.WriteLine("[KERNEL] Preparing interrupt foundation.");
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
        System.Kernel.Interrupts.Enable();
        System.Kernel.Interrupts.Idle();
    }
}
