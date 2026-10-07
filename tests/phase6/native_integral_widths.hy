namespace Demo {
    public class Program {
        public static int Main() {
            sbyte signedByte = (sbyte)255;
            byte unsignedByte = (byte)-1;
            short signedShort = (short)65535;
            ushort unsignedShort = (ushort)-1;
            uint unsignedInt = (uint)-1;
            long signedLong = (long)-1;
            ulong unsignedLong = (ulong)-1;

            System.Console.WriteLine(signedByte);
            System.Console.WriteLine(unsignedByte);
            System.Console.WriteLine(signedShort);
            System.Console.WriteLine(unsignedShort);
            System.Console.WriteLine(unsignedInt);
            System.Console.WriteLine(signedLong);
            System.Console.WriteLine(unsignedLong);
            System.Console.WriteLine(sizeof(byte));
            System.Console.WriteLine(sizeof(short));
            System.Console.WriteLine(sizeof(uint));
            System.Console.WriteLine(sizeof(ulong));

            if (signedByte != -1) { return 1; }
            if (unsignedByte != 255) { return 2; }
            if (signedShort != -1) { return 3; }
            if (unsignedShort != 65535) { return 4; }
            if (unsignedInt < 1) { return 5; }
            if (unsignedLong / (ulong)2 < (ulong)100) { return 6; }
            if (sizeof(sbyte) != (nuint)1) { return 7; }
            if (sizeof(ushort) != (nuint)2) { return 8; }
            if (sizeof(int) != (nuint)4) { return 9; }
            if (sizeof(nint) != (nuint)8) { return 10; }
            return 42;
        }
    }
}
