namespace SdkDemo.Core {
    public class Report {
        public static string FromText(string text) {
            return "bytes=" + text.Length;
        }

        public static string Title() {
            return "SdkDemo.Core";
        }
    }
}
