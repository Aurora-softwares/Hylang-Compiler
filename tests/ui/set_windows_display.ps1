$ErrorActionPreference = 'Stop'
# The default hosted VM desktop is only 1024 pixels wide. Use a supported
# virtual-display mode so a 1120-pixel WinUI client is actually rendered.
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class UiTestDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct Mode {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string device;
        public short specVersion, driverVersion, size, driverExtra;
        public uint fields;
        public int x, y;
        public uint orientation, fixedOutput;
        public short color, duplex, yResolution, ttOption, collate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string form;
        public short logPixels;
        public uint bits, width, height, flags, frequency, icmMethod, icmIntent, media, dither, reserved1, reserved2, panningWidth, panningHeight;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string device, int mode, ref Mode settings);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int ChangeDisplaySettings(ref Mode settings, uint flags);
    public static string Configure() {
        var current = new Mode { size = (short)Marshal.SizeOf<Mode>() };
        if (!EnumDisplaySettings(null, -1, ref current)) throw new Exception("Cannot read virtual desktop mode");
        if (current.width >= 1280 && current.height >= 800) return current.width + "x" + current.height;
        for (int i = 0; i < 1000; i++) {
            var candidate = new Mode { size = (short)Marshal.SizeOf<Mode>() };
            if (!EnumDisplaySettings(null, i, ref candidate)) break;
            if (candidate.width < 1280 || candidate.height < 800 || candidate.width > 1920 || candidate.height > 1200) continue;
            int status = ChangeDisplaySettings(ref candidate, 0);
            if (status == 0) return candidate.width + "x" + candidate.height;
        }
        throw new Exception("No supported virtual desktop mode is large enough for native UI tests");
    }
}
'@
Write-Host "UI test desktop: $([UiTestDisplay]::Configure())"
