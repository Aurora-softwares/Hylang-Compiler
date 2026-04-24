using System.Runtime;

public class Program {
    public static void Main(string[] args) {
        byte[] data = new byte[16];
        BinaryPrimitives.WriteUInt64LE(data, 0, 72623859790382856);
        BinaryPrimitives.WriteInt64BE(data, 8, -72623859790382856);

        System.Console.WriteLine("U=" + BinaryPrimitives.ReadUInt64LE(data, 0));
        System.Console.WriteLine("I=" + BinaryPrimitives.ReadInt64BE(data, 8));
    }
}
