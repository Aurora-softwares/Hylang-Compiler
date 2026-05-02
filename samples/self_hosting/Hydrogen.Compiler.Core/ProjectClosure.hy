using Hydrogen.Compiler.Core;

namespace Hydrogen.Compiler.Core {
    public class ProjectClosure {
        private string[] projects;
        private string[] sources;

        public ProjectClosure(string[] inputProjects, string[] inputSources) {
            projects = inputProjects;
            sources = inputSources;
        }

        public string[] Projects() { return projects; }
        public string[] Sources() { return sources; }

        public static ProjectClosure Collect(string projectPath) {
            return CollectProject(projectPath, new string[0], new string[0], new string[0]);
        }

        private static ProjectClosure CollectProject(string projectPath, string[] stack, string[] projects, string[] sources) {
            if (Contains(projects, projectPath)) {
                return new ProjectClosure(projects, sources);
            }
            if (Contains(stack, projectPath)) {
                // Cycle detected; represent as a single project list containing the cycle marker.
                string[] cycle = new string[1];
                cycle[0] = "<cycle:" + projectPath + ">";
                return new ProjectClosure(cycle, new string[0]);
            }

            string[] nextStack = Append(stack, stack.Length, projectPath);

            HyprojManifest manifest = HyprojManifest.Load(projectPath);
            string baseDir = PathUtils.DirName(projectPath);

            // Recurse references first
            string[] refs = manifest.ProjectReferences();
            int i = 0;
            while (i < refs.Length) {
                string refPath = PathUtils.Join(baseDir, refs[i]);
                ProjectClosure next = CollectProject(refPath, nextStack, projects, sources);
                if (IsCycleMarker(next.Projects())) {
                    return next;
                }
                projects = next.Projects();
                sources = next.Sources();
                i = i + 1;
            }

            projects = Append(projects, projects.Length, projectPath);

            // Add sources
            string[] src = manifest.Sources();
            int s = 0;
            while (s < src.Length) {
                sources = Append(sources, sources.Length, PathUtils.Join(baseDir, src[s]));
                s = s + 1;
            }

            return new ProjectClosure(projects, sources);
        }

        private static bool IsCycleMarker(string[] projects) {
            if (projects.Length == 0) { return false; }
            return StartsWith(projects[0], "<cycle:");
        }

        private static bool StartsWith(string text, string prefix) {
            if (text.Length < prefix.Length) { return false; }
            int i = 0;
            while (i < prefix.Length) {
                if (text[i] != prefix[i]) { return false; }
                i = i + 1;
            }
            return true;
        }

        private static bool Contains(string[] items, string value) {
            int i = 0;
            while (i < items.Length) {
                if (items[i] == value) {
                    return true;
                }
                i = i + 1;
            }
            return false;
        }

        private static string[] Append(string[] items, int count, string item) {
            string[] next = new string[count + 1];
            int i = 0;
            while (i < count) {
                next[i] = items[i];
                i = i + 1;
            }
            next[count] = item;
            return next;
        }
    }
}
