namespace TextReport {
    public class ReportFormatter {
        public static string BuildSummary(string contents) {
            int characters = 0;
            for (int index = 0; index < contents.Length; index = index + 1) {
                characters = characters + 1;
            }

            return "characters=" + characters;
        }
    }
}
