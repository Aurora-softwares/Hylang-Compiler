namespace Hydrogen.Compiler.Core {
    // A deliberately small, static catalog. Package URLs are derived from validated
    // identifiers, never accepted from the catalog or a package manifest.
    public class PackageRegistry {
        private string[] ids;
        private string[] versions;
        private string[] hashes;
        private bool valid;

        public PackageRegistry(string[] inputIds, string[] inputVersions, string[] inputHashes, bool inputValid) {
            ids = inputIds;
            versions = inputVersions;
            hashes = inputHashes;
            valid = inputValid;
        }

        public bool Valid() { return valid; }
        public int Count() { return ids.Length; }
        public string Id(int index) { return ids[index]; }
        public string Version(int index) { return versions[index]; }
        public string Hash(int index) { return hashes[index]; }

        public string FindHash(string id, string version) {
            int i = 0;
            while (i < ids.Length) {
                if (ids[i] == id && versions[i] == version) { return hashes[i]; }
                i = i + 1;
            }
            return "";
        }

        public static PackageRegistry Parse(string text) {
            string[] ids = new string[0];
            string[] versions = new string[0];
            string[] hashes = new string[0];
            string header = "hydrogen-registry-v1\n";
            if (!StartsWith(text, header) || text.Length > 1048576) {
                return new PackageRegistry(ids, versions, hashes, false);
            }
            int at = header.Length;
            while (at < text.Length) {
                int end = Find(text, "\n", at);
                if (end < 0) { return new PackageRegistry(ids, versions, hashes, false); }
                string line = Slice(text, at, end - at);
                if (line != "") {
                    int a = Find(line, " ", 0);
                    int b = a < 0 ? -1 : Find(line, " ", a + 1);
                    if (a < 1 || b < a + 2 || Find(line, " ", b + 1) >= 0) {
                        return new PackageRegistry(ids, versions, hashes, false);
                    }
                    string id = Slice(line, 0, a);
                    string version = Slice(line, a + 1, b - a - 1);
                    string hash = Slice(line, b + 1, line.Length - b - 1);
                    if (!HyprojManifest.ValidPackagePart(id) || !HyprojManifest.ValidPackagePart(version) ||
                        !ValidHash(hash) || Duplicate(ids, versions, id, version)) {
                        return new PackageRegistry(ids, versions, hashes, false);
                    }
                    ids = Append(ids, id);
                    versions = Append(versions, version);
                    hashes = Append(hashes, hash);
                }
                at = end + 1;
            }
            return new PackageRegistry(ids, versions, hashes, true);
        }

        private static bool ValidHash(string text) {
            if (text.Length != 64) { return false; }
            int i = 0;
            while (i < text.Length) {
                if (Find("0123456789abcdef", text[i], 0) < 0) { return false; }
                i = i + 1;
            }
            return true;
        }

        private static bool Duplicate(string[] ids, string[] versions, string id, string version) {
            int i = 0;
            while (i < ids.Length) {
                if (ids[i] == id && versions[i] == version) { return true; }
                i = i + 1;
            }
            return false;
        }

        private static string[] Append(string[] input, string value) {
            string[] result = new string[input.Length + 1];
            int i = 0;
            while (i < input.Length) { result[i] = input[i]; i = i + 1; }
            result[input.Length] = value;
            return result;
        }

        private static bool StartsWith(string text, string prefix) {
            if (text.Length < prefix.Length) { return false; }
            int i = 0;
            while (i < prefix.Length) { if (text[i] != prefix[i]) { return false; } i = i + 1; }
            return true;
        }

        private static int Find(string text, string needle, int start) {
            int i = start;
            while (i <= text.Length - needle.Length) {
                int j = 0;
                while (j < needle.Length && text[i + j] == needle[j]) { j = j + 1; }
                if (j == needle.Length) { return i; }
                i = i + 1;
            }
            return -1;
        }

        private static string Slice(string text, int start, int length) {
            string result = "";
            int i = 0;
            while (i < length) { result = result + text[start + i]; i = i + 1; }
            return result;
        }
    }
}
