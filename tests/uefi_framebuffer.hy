public class Program {
    public static void Main(string[] args) {
        System.Console.WriteLine("[KERNEL] Preparing framebuffer handoff.");
        System.Uefi.ExitBootServices();
        System.Kernel.MemoryMap.Initialize();
        System.Kernel.Memory.Initialize();
        System.Kernel.VirtualMemory.Initialize();
        System.Kernel.VirtualMemory.ApplyPolicy();
        System.Kernel.Heap.Initialize();
        System.Kernel.Framebuffer.Initialize();
        System.Kernel.Framebuffer.WriteLine("[KERNEL] Framebuffer console active.");
        System.Kernel.Framebuffer.WriteLine("[KERNEL] Direct pixels after ExitBootServices.");
        System.Kernel.Halt();
    }
}
