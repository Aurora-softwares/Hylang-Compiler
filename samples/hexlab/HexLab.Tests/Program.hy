using HexLab.Core;
using System.Runtime;
using System.Testing;

public class Program {
    public static int Main(string[] args) {
        TestDump();
        TestInspectPng();
        TestInspectZip();
        TestDiffAndSearch();
        TestSlice();
        return 0;
    }

    public static void TestDump() {
        byte[] data = new byte[4];
        data[0] = 137;
        data[1] = 80;
        data[2] = 78;
        data[3] = 71;
        Assert.Equal("0: 89 50 4E 47", HexLab.Dump(data, 16, 0, -1), "dump output should match");
    }

    public static void TestInspectPng() {
        byte[] data = new byte[24];
        data[0] = 137;
        data[1] = 80;
        data[2] = 78;
        data[3] = 71;
        data[4] = 13;
        data[5] = 10;
        data[6] = 26;
        data[7] = 10;
        BinaryPrimitives.WriteUInt32BE(data, 16, 1);
        BinaryPrimitives.WriteUInt32BE(data, 20, 1);
        Assert.Equal("format=PNG width=1 height=1", HexLab.Inspect(data), "png inspect should match");
    }

    public static void TestInspectZip() {
        byte[] data = new byte[30];
        data[0] = 80;
        data[1] = 75;
        data[2] = 3;
        data[3] = 4;
        BinaryPrimitives.WriteUInt16LE(data, 8, 0);
        BinaryPrimitives.WriteUInt16LE(data, 26, 4);
        BinaryPrimitives.WriteUInt16LE(data, 28, 0);
        Assert.Equal("format=ZIP method=0 name_length=4 extra_length=0", HexLab.Inspect(data), "zip inspect should match");
    }

    public static void TestDiffAndSearch() {
        byte[] left = new byte[4];
        left[0] = 1;
        left[1] = 2;
        left[2] = 3;
        left[3] = 4;

        byte[] right = new byte[4];
        right[0] = 1;
        right[1] = 2;
        right[2] = 9;
        right[3] = 4;

        Assert.Equal("diff offset=2 left=03 right=09", HexLab.Diff(left, right), "diff should report first mismatch");
        Assert.Equal("found offset=1", HexLab.Search(left, "0203"), "search should find the pattern");
    }

    public static void TestSlice() {
        string inputPath = "hexlab_test_input.bin";
        string outputPath = "hexlab_test_output.bin";
        byte[] data = new byte[6];
        data[0] = 10;
        data[1] = 11;
        data[2] = 12;
        data[3] = 13;
        data[4] = 14;
        data[5] = 15;
        System.IO.File.WriteAllBytes(inputPath, data);
        Assert.Equal("wrote=3", HexLab.SliceFile(inputPath, 2, 3, outputPath), "slice should report bytes written");
        byte[] sliced = System.IO.File.ReadAllBytes(outputPath);
        Assert.Equal(3, sliced.Length, "slice length should match");
        Assert.Equal(12, sliced[0], "first sliced byte should match");
        Assert.Equal(14, sliced[2], "last sliced byte should match");
    }
}
