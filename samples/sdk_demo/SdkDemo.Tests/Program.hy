using SdkDemo.Core;
using System.Testing;

public class Program {
    public static int Main(string[] args) {
        Assert.Equal("bytes=5", Report.FromText("hello"), "report bytes");
        Assert.Equal("SdkDemo.Core", Report.Title(), "report title");
        return 0;
    }
}
