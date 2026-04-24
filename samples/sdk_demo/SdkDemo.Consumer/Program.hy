using SdkDemo.Core;

public class Program {
    public static void Main(string[] args) {
        System.Console.WriteLine(Report.Title());
        System.Console.WriteLine(Report.FromText("consumer"));
    }
}
