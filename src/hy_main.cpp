#include "hylang/hylang.hpp"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

using std::string;
using std::vector;

struct CliManifest {
    int format = 1;
    string name;
    string version = "0.1.0";
    string type = "exe";
    vector<fs::path> sources;
    vector<fs::path> members;
};

string trim(string value) {
    const auto not_space = [](unsigned char ch) { return !std::isspace(ch); };
    value.erase(value.begin(), std::find_if(value.begin(), value.end(), not_space));
    value.erase(std::find_if(value.rbegin(), value.rend(), not_space).base(), value.end());
    return value;
}

string trim_right(string value) {
    const auto not_space = [](unsigned char ch) { return !std::isspace(ch); };
    value.erase(std::find_if(value.rbegin(), value.rend(), not_space).base(), value.end());
    return value;
}

bool starts_with(const string& value, const string& prefix) {
    return value.rfind(prefix, 0) == 0;
}

bool read_text_file(const fs::path& path, string& output) {
    std::ifstream input(path);
    if (!input) {
        return false;
    }
    std::ostringstream buffer;
    buffer << input.rdbuf();
    output = buffer.str();
    return true;
}

bool write_text_file(const fs::path& path, const string& contents) {
    if (!path.parent_path().empty()) {
        fs::create_directories(path.parent_path());
    }
    std::ofstream output(path);
    if (!output) {
        return false;
    }
    output << contents;
    return true;
}

std::optional<string> parse_quoted_string(const string& raw) {
    if (raw.size() >= 2 && raw.front() == '"' && raw.back() == '"') {
        return raw.substr(1, raw.size() - 2);
    }
    return std::nullopt;
}

vector<fs::path> parse_path_array(const string& raw) {
    vector<fs::path> result;
    if (raw.size() < 2 || raw.front() != '[' || raw.back() != ']') {
        return result;
    }
    string inner = trim(raw.substr(1, raw.size() - 2));
    std::size_t cursor = 0;
    while (cursor < inner.size()) {
        while (cursor < inner.size() && std::isspace(static_cast<unsigned char>(inner[cursor]))) {
            ++cursor;
        }
        if (cursor >= inner.size()) {
            break;
        }
        if (inner[cursor] != '"') {
            break;
        }
        ++cursor;
        string item;
        while (cursor < inner.size() && inner[cursor] != '"') {
            item.push_back(inner[cursor++]);
        }
        if (cursor >= inner.size()) {
            break;
        }
        ++cursor;
        result.emplace_back(item);
        while (cursor < inner.size() && std::isspace(static_cast<unsigned char>(inner[cursor]))) {
            ++cursor;
        }
        if (cursor < inner.size() && inner[cursor] == ',') {
            ++cursor;
        }
    }
    return result;
}

std::optional<CliManifest> load_cli_manifest(const fs::path& path) {
    string text;
    if (!read_text_file(path, text)) {
        return std::nullopt;
    }

    CliManifest manifest;
    std::istringstream input(text);
    string line;
    string current_section;
    while (std::getline(input, line)) {
        line = trim(line);
        if (line.empty() || starts_with(line, "#") || starts_with(line, "//")) {
            continue;
        }
        if (line.front() == '[' && line.back() == ']') {
            current_section = trim(line.substr(1, line.size() - 2));
            continue;
        }
        const auto equals = line.find('=');
        if (equals == string::npos) {
            continue;
        }
        const string key = trim(line.substr(0, equals));
        const string value = trim(line.substr(equals + 1));
        if (!current_section.empty()) {
            continue;
        }
        if (key == "format") {
            manifest.format = value == "2" ? 2 : 1;
        } else if (key == "name") {
            if (auto parsed = parse_quoted_string(value)) {
                manifest.name = *parsed;
            }
        } else if (key == "version") {
            if (auto parsed = parse_quoted_string(value)) {
                manifest.version = *parsed;
            }
        } else if (key == "type") {
            if (auto parsed = parse_quoted_string(value)) {
                manifest.type = *parsed;
            }
        } else if (key == "sources") {
            manifest.sources = parse_path_array(value);
        } else if (key == "members") {
            manifest.members = parse_path_array(value);
        }
    }

    if (manifest.name.empty()) {
        manifest.name = path.stem().string();
    }
    return manifest;
}

bool is_workspace_manifest(const fs::path& path) {
    const auto manifest = load_cli_manifest(path);
    return manifest.has_value() && manifest->type == "workspace";
}

void collect_workspace_members(const fs::path& path, vector<fs::path>& members) {
    const auto manifest = load_cli_manifest(path);
    if (!manifest.has_value()) {
        return;
    }
    if (manifest->type != "workspace") {
        members.push_back(path);
        return;
    }
    const fs::path base = path.parent_path();
    for (const auto& member : manifest->members) {
        const fs::path member_path = fs::weakly_canonical(base / member);
        if (is_workspace_manifest(member_path)) {
            collect_workspace_members(member_path, members);
        } else {
            members.push_back(member_path);
        }
    }
}

string escape_json(const string& value) {
    std::ostringstream out;
    for (char ch : value) {
        switch (ch) {
            case '\\':
                out << "\\\\";
                break;
            case '"':
                out << "\\\"";
                break;
            case '\n':
                out << "\\n";
                break;
            case '\r':
                out << "\\r";
                break;
            case '\t':
                out << "\\t";
                break;
            default:
                out << ch;
                break;
        }
    }
    return out.str();
}

void print_json_diagnostics(const vector<hylang::Diagnostic>& diagnostics) {
    std::cout << "[\n";
    for (std::size_t index = 0; index < diagnostics.size(); ++index) {
        const auto& diagnostic = diagnostics[index];
        std::cout << "  {\n";
        std::cout << "    \"file\": \"" << escape_json(diagnostic.file.string()) << "\",\n";
        std::cout << "    \"line\": " << diagnostic.line << ",\n";
        std::cout << "    \"column\": " << diagnostic.column << ",\n";
        std::cout << "    \"severity\": \"" << (diagnostic.is_warning ? "warning" : "error") << "\",\n";
        std::cout << "    \"message\": \"" << escape_json(diagnostic.message) << "\"\n";
        std::cout << "  }";
        if (index + 1 < diagnostics.size()) {
            std::cout << ",";
        }
        std::cout << "\n";
    }
    std::cout << "]\n";
}

std::optional<fs::path> resolve_default_target() {
    vector<fs::path> manifests;
    for (const auto& entry : fs::directory_iterator(fs::current_path())) {
        if (entry.is_regular_file() && entry.path().extension() == ".hyproj") {
            manifests.push_back(entry.path());
        }
    }
    if (manifests.size() == 1) {
        return manifests.front();
    }
    return std::nullopt;
}

void collect_format_files(const fs::path& path, vector<fs::path>& files) {
    if (!fs::exists(path)) {
        return;
    }
    if (fs::is_regular_file(path)) {
        if (path.extension() == ".hy" || path.extension() == ".hyproj") {
            files.push_back(path);
        }
        return;
    }
    for (const auto& entry : fs::recursive_directory_iterator(path)) {
        if (!entry.is_regular_file()) {
            continue;
        }
        if (entry.path().extension() == ".hy" || entry.path().extension() == ".hyproj") {
            files.push_back(entry.path());
        }
    }
}

string format_hy_source(const string& input) {
    std::istringstream stream(input);
    vector<string> lines;
    string line;
    while (std::getline(stream, line)) {
        lines.push_back(trim_right(line));
    }

    vector<string> using_lines;
    vector<string> body_lines;
    bool in_using_block = true;
    for (const auto& current_line : lines) {
        const string trimmed = trim(current_line);
        if (in_using_block && (trimmed.empty() || starts_with(trimmed, "using "))) {
            if (!trimmed.empty()) {
                using_lines.push_back(trimmed);
            }
            continue;
        }
        in_using_block = false;
        body_lines.push_back(current_line);
    }

    std::sort(using_lines.begin(), using_lines.end());
    using_lines.erase(std::unique(using_lines.begin(), using_lines.end()), using_lines.end());

    std::ostringstream out;
    for (const auto& using_line : using_lines) {
        out << using_line << "\n";
    }
    if (!using_lines.empty() && !body_lines.empty()) {
        out << "\n";
    }

    bool last_blank = false;
    for (const auto& body_line : body_lines) {
        const string trimmed = trim(body_line);
        if (trimmed.empty()) {
            if (!last_blank) {
                out << "\n";
            }
            last_blank = true;
            continue;
        }
        out << body_line << "\n";
        last_blank = false;
    }
    if (body_lines.empty() && using_lines.empty()) {
        out << "\n";
    }
    return out.str();
}

string format_hyproj_v2(const string& input) {
    if (input.find("format = 2") == string::npos) {
        return input;
    }

    std::map<string, string> root;
    std::map<string, string> package;
    std::map<string, string> dependencies;

    std::istringstream stream(input);
    string line;
    string section;
    while (std::getline(stream, line)) {
        line = trim(line);
        if (line.empty() || starts_with(line, "#") || starts_with(line, "//")) {
            continue;
        }
        if (line.front() == '[' && line.back() == ']') {
            section = trim(line.substr(1, line.size() - 2));
            continue;
        }
        const auto equals = line.find('=');
        if (equals == string::npos) {
            continue;
        }
        const string key = trim(line.substr(0, equals));
        const string value = trim(line.substr(equals + 1));
        if (section.empty()) {
            root[key] = value;
        } else if (section == "package") {
            package[key] = value;
        } else if (section == "dependencies") {
            dependencies[key] = value;
        }
    }

    std::ostringstream out;
    const vector<string> root_order = {"format", "name", "version", "type", "sources", "project_references", "members"};
    for (const auto& key : root_order) {
        const auto found = root.find(key);
        if (found != root.end()) {
            out << key << " = " << found->second << "\n";
        }
    }
    if (!package.empty()) {
        out << "\n[package]\n";
        const vector<string> package_order = {"id", "description", "authors", "license"};
        for (const auto& key : package_order) {
            const auto found = package.find(key);
            if (found != package.end()) {
                out << key << " = " << found->second << "\n";
            }
        }
    }
    if (!dependencies.empty()) {
        out << "\n[dependencies]\n";
        for (const auto& [key, value] : dependencies) {
            out << key << " = " << value << "\n";
        }
    }
    return out.str();
}

int format_paths(const vector<fs::path>& input_paths, bool check_only) {
    vector<fs::path> files;
    if (input_paths.empty()) {
        collect_format_files(fs::current_path(), files);
    } else {
        for (const auto& path : input_paths) {
            collect_format_files(path, files);
        }
    }

    std::sort(files.begin(), files.end());
    files.erase(std::unique(files.begin(), files.end()), files.end());

    bool changed = false;
    for (const auto& file : files) {
        string contents;
        if (!read_text_file(file, contents)) {
            std::cerr << "could not read " << file << "\n";
            return 1;
        }
        string formatted = file.extension() == ".hyproj" ? format_hyproj_v2(contents) : format_hy_source(contents);
        if (formatted != contents) {
            changed = true;
            if (!check_only && !write_text_file(file, formatted)) {
                std::cerr << "could not write " << file << "\n";
                return 1;
            }
        }
    }
    return check_only && changed ? 1 : 0;
}

string render_v2_manifest(const string& name,
                          const string& type,
                          const vector<string>& sources,
                          const vector<string>& members = {}) {
    std::ostringstream out;
    out << "format = 2\n";
    out << "name = \"" << name << "\"\n";
    out << "version = \"0.1.0\"\n";
    out << "type = \"" << type << "\"\n";
    if (!members.empty()) {
        out << "members = [";
        for (std::size_t index = 0; index < members.size(); ++index) {
            if (index > 0) {
                out << ", ";
            }
            out << "\"" << members[index] << "\"";
        }
        out << "]\n";
    } else {
        out << "sources = [";
        for (std::size_t index = 0; index < sources.size(); ++index) {
            if (index > 0) {
                out << ", ";
            }
            out << "\"" << sources[index] << "\"";
        }
        out << "]\n";
        out << "project_references = []\n";
    }
    out << "\n[package]\n";
    out << "id = \"" << name << "\"\n";
    out << "description = \"\"\n";
    out << "authors = []\n";
    out << "license = \"\"\n";
    return out.str();
}

int scaffold_project(const string& kind, const fs::path& destination) {
    if (fs::exists(destination)) {
        std::cerr << "destination already exists: " << destination << "\n";
        return 1;
    }

    fs::create_directories(destination);
    const string name = destination.filename().string();
    if (kind == "workspace") {
        if (!write_text_file(destination / (name + ".hyproj"), render_v2_manifest(name, "workspace", {}, {}))) {
            std::cerr << "could not write workspace manifest\n";
            return 1;
        }
        return 0;
    }

    const string manifest_type = kind == "test" ? "test" : (kind == "lib" ? "lib" : "exe");
    const string source_file = kind == "lib" ? "Library.hy" : "Program.hy";
    if (!write_text_file(destination / (name + ".hyproj"), render_v2_manifest(name, manifest_type, {source_file}))) {
        std::cerr << "could not write manifest\n";
        return 1;
    }

    string source;
    if (kind == "lib") {
        source =
            "namespace " + name + " {\n"
            "    public class Library {\n"
            "        public static string Name() {\n"
            "            return \"" + name + "\";\n"
            "        }\n"
            "    }\n"
            "}\n";
    } else if (kind == "test") {
        source =
            "using System.Testing;\n\n"
            "public class Program {\n"
            "    public static int Main(string[] args) {\n"
            "        Assert.True(true, \"scaffolded test should pass\");\n"
            "        return 0;\n"
            "    }\n"
            "}\n";
    } else {
        source =
            "public class Program {\n"
            "    public static void Main(string[] args) {\n"
            "        System.Console.WriteLine(\"Hello from " + name + "!\");\n"
            "    }\n"
            "}\n";
    }

    if (!write_text_file(destination / source_file, source)) {
        std::cerr << "could not write source file\n";
        return 1;
    }

    return 0;
}

int handle_build(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: hy build <file.hy|project.hyproj> [--target exe|lib] [-o output] [--debug]\n";
        return 1;
    }

    const fs::path target = argv[2];
    if (target.extension() == ".hyproj" && is_workspace_manifest(target)) {
        vector<fs::path> members;
        collect_workspace_members(target, members);
        int status = 0;
        for (const auto& member : members) {
            hylang::BuildOptions options;
            options.input_path = member;
            for (int index = 3; index < argc; ++index) {
                const string argument = argv[index];
                if (argument == "--debug") {
                    options.debug = true;
                }
            }
            const auto result = hylang::build_target(options);
            if (!result.success) {
                std::cerr << hylang::format_diagnostics(result.diagnostics);
                status = 1;
                continue;
            }
            std::cout << result.output_path.string() << "\n";
        }
        return status;
    }

    hylang::BuildOptions options;
    options.input_path = target;
    for (int index = 3; index < argc; ++index) {
        const string argument = argv[index];
        if (argument == "--target") {
            if (index + 1 >= argc) {
                std::cerr << "missing value after --target\n";
                return 1;
            }
            options.forced_target = std::string(argv[++index]);
        } else if (argument == "-o" || argument == "--output") {
            if (index + 1 >= argc) {
                std::cerr << "missing value after " << argument << "\n";
                return 1;
            }
            options.output_path = fs::path(argv[++index]);
        } else if (argument == "--debug") {
            options.debug = true;
        } else {
            std::cerr << "unknown argument: " << argument << "\n";
            return 1;
        }
    }

    const auto result = hylang::build_target(options);
    if (!result.success) {
        std::cerr << hylang::format_diagnostics(result.diagnostics);
        return 1;
    }
    std::cout << result.output_path.string() << "\n";
    return 0;
}

int handle_run(int argc, char** argv) {
    if (argc < 3) {
        std::cerr << "usage: hy run <file.hy|project.hyproj> [-- args...]\n";
        return 1;
    }
    hylang::RunOptions options;
    options.input_path = argv[2];
    bool after_separator = false;
    for (int index = 3; index < argc; ++index) {
        const string argument = argv[index];
        if (argument == "--" && !after_separator) {
            after_separator = true;
            continue;
        }
        options.args.push_back(argument);
    }
    const auto result = hylang::run_target(options);
    if (!result.success) {
        std::cerr << hylang::format_diagnostics(result.diagnostics);
        return 1;
    }
    return result.exit_code;
}

int handle_check(int argc, char** argv) {
    fs::path target;
    bool emit_json = false;
    if (argc >= 3 && argv[2][0] != '-') {
        target = argv[2];
    } else {
        auto resolved = resolve_default_target();
        if (!resolved.has_value()) {
            std::cerr << "usage: hy check <file.hy|project.hyproj> [--json]\n";
            return 1;
        }
        target = *resolved;
    }

    for (int index = (argc >= 3 && argv[2][0] != '-') ? 3 : 2; index < argc; ++index) {
        const string argument = argv[index];
        if (argument == "--json") {
            emit_json = true;
        } else {
            std::cerr << "unknown argument: " << argument << "\n";
            return 1;
        }
    }

    hylang::CheckOptions options;
    options.input_path = target;
    const auto result = hylang::check_target(options);
    if (emit_json) {
        print_json_diagnostics(result.diagnostics);
    } else if (!result.diagnostics.empty()) {
        std::cerr << hylang::format_diagnostics(result.diagnostics);
    }
    return result.success ? 0 : 1;
}

int handle_test(int argc, char** argv) {
    fs::path target;
    if (argc >= 3) {
        target = argv[2];
    } else {
        auto resolved = resolve_default_target();
        if (!resolved.has_value()) {
            std::cerr << "usage: hy test [project.hyproj]\n";
            return 1;
        }
        target = *resolved;
    }
    hylang::TestOptions options;
    options.input_path = target;
    const auto result = hylang::test_target(options);
    if (!result.diagnostics.empty()) {
        std::cerr << hylang::format_diagnostics(result.diagnostics);
    }
    return result.success ? 0 : 1;
}

int handle_fmt(int argc, char** argv) {
    bool check_only = false;
    vector<fs::path> paths;
    for (int index = 2; index < argc; ++index) {
        const string argument = argv[index];
        if (argument == "--check") {
            check_only = true;
        } else {
            paths.emplace_back(argument);
        }
    }
    return format_paths(paths, check_only);
}

int handle_package(int argc, char** argv) {
    if (argc < 4) {
        std::cerr << "usage: hy package pack <target> [-o output]\n";
        std::cerr << "   or: hy package add <target.hyproj> <path>\n";
        return 1;
    }
    const string command = argv[2];
    if (command == "pack") {
        fs::path target = argv[3];
        fs::path output;
        for (int index = 4; index < argc; ++index) {
            const string argument = argv[index];
            if ((argument == "-o" || argument == "--output") && index + 1 < argc) {
                output = argv[++index];
            } else {
                std::cerr << "unknown argument: " << argument << "\n";
                return 1;
            }
        }
        if (output.empty()) {
            if (target.extension() == ".hyproj") {
                const auto manifest = load_cli_manifest(target);
                const string stem = manifest.has_value() ? manifest->name + "-" + manifest->version : target.stem().string();
                output = target.parent_path() / ".hylang" / "packages" / (stem + ".hypkg");
            } else {
                output = target.parent_path() / ".hylang" / "packages" / (target.stem().string() + ".hypkg");
            }
        }

        vector<fs::path> files;
        if (target.extension() == ".hyproj") {
            files.push_back(target);
            for (const auto& entry : fs::directory_iterator(target.parent_path())) {
                if (entry.is_regular_file() &&
                    (entry.path().extension() == ".hy" || entry.path().extension() == ".hyproj")) {
                    files.push_back(entry.path());
                }
            }
        } else {
            files.push_back(target);
        }
        std::sort(files.begin(), files.end());
        files.erase(std::unique(files.begin(), files.end()), files.end());

        std::ostringstream archive;
        archive << "HYLANG_PACKAGE_V1\n";
        for (const auto& file : files) {
            string contents;
            if (!read_text_file(file, contents)) {
                std::cerr << "could not read " << file << "\n";
                return 1;
            }
            archive << "FILE " << file.filename().string() << " " << contents.size() << "\n";
            archive << contents << "\n";
        }
        if (!write_text_file(output, archive.str())) {
            std::cerr << "could not write package " << output << "\n";
            return 1;
        }
        std::cout << output.string() << "\n";
        return 0;
    }

    if (command == "add") {
        if (argc < 5) {
            std::cerr << "usage: hy package add <target.hyproj> <path>\n";
            return 1;
        }
        const fs::path target = argv[3];
        const fs::path dependency_path = argv[4];
        string contents;
        if (!read_text_file(target, contents)) {
            std::cerr << "could not read " << target << "\n";
            return 1;
        }
        if (contents.find("format = 2") == string::npos) {
            std::cerr << "hy package add only supports v2 manifests\n";
            return 1;
        }
        const auto dependency_manifest = load_cli_manifest(dependency_path);
        const string dependency_name = dependency_manifest.has_value() ? dependency_manifest->name : dependency_path.stem().string();
        const string relative_path = fs::relative(dependency_path, target.parent_path()).string();
        if (contents.find("[dependencies]") == string::npos) {
            contents += "\n[dependencies]\n";
        }
        contents += dependency_name + " = { path = \"" + relative_path + "\" }\n";
        contents = format_hyproj_v2(contents);
        if (!write_text_file(target, contents)) {
            std::cerr << "could not write " << target << "\n";
            return 1;
        }
        return 0;
    }

    std::cerr << "unknown package command: " << command << "\n";
    return 1;
}

void print_usage() {
    std::cerr << "usage:\n";
    std::cerr << "  hy new app|lib|tool|test|workspace <name>\n";
    std::cerr << "  hy build <file.hy|project.hyproj> [--target exe|lib] [-o output] [--debug]\n";
    std::cerr << "  hy run <file.hy|project.hyproj> [-- args...]\n";
    std::cerr << "  hy test [project.hyproj]\n";
    std::cerr << "  hy fmt <path...> [--check]\n";
    std::cerr << "  hy check <file.hy|project.hyproj> [--json]\n";
    std::cerr << "  hy package pack <target> [-o output]\n";
    std::cerr << "  hy package add <target.hyproj> <path>\n";
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) {
        print_usage();
        return 1;
    }

    const string command = argv[1];
    if (command == "new") {
        if (argc < 4) {
            print_usage();
            return 1;
        }
        return scaffold_project(argv[2], fs::path(argv[3]));
    }
    if (command == "build") {
        return handle_build(argc, argv);
    }
    if (command == "run") {
        return handle_run(argc, argv);
    }
    if (command == "check") {
        return handle_check(argc, argv);
    }
    if (command == "test") {
        return handle_test(argc, argv);
    }
    if (command == "fmt") {
        return handle_fmt(argc, argv);
    }
    if (command == "package") {
        return handle_package(argc, argv);
    }

    print_usage();
    return 1;
}
