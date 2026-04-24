#include "hylang/hylang.hpp"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace fs = std::filesystem;

namespace {

using std::string;
using std::vector;

struct CliManifest {
    struct Dependency {
        string path;
        string id;
        string version;
    };

    int format = 1;
    string name;
    string version = "0.1.0";
    string type = "exe";
    string package_id;
    string description;
    string authors = "[]";
    string license;
    vector<fs::path> sources;
    vector<fs::path> project_references;
    vector<fs::path> members;
    std::map<string, Dependency> dependencies;
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

string quote_string(const string& value) {
    return "\"" + value + "\"";
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

std::map<string, string> parse_inline_table(const string& raw) {
    std::map<string, string> result;
    if (raw.size() < 2 || raw.front() != '{' || raw.back() != '}') {
        return result;
    }
    string inner = trim(raw.substr(1, raw.size() - 2));
    std::size_t cursor = 0;
    while (cursor < inner.size()) {
        while (cursor < inner.size() && std::isspace(static_cast<unsigned char>(inner[cursor]))) {
            ++cursor;
        }
        const std::size_t key_start = cursor;
        while (cursor < inner.size() && inner[cursor] != '=' && inner[cursor] != ',') {
            ++cursor;
        }
        if (cursor >= inner.size() || inner[cursor] != '=') {
            break;
        }
        const string key = trim(inner.substr(key_start, cursor - key_start));
        ++cursor;
        while (cursor < inner.size() && std::isspace(static_cast<unsigned char>(inner[cursor]))) {
            ++cursor;
        }
        string value;
        if (cursor < inner.size() && inner[cursor] == '"') {
            const std::size_t value_start = cursor++;
            while (cursor < inner.size() && inner[cursor] != '"') {
                ++cursor;
            }
            if (cursor < inner.size()) {
                ++cursor;
            }
            value = inner.substr(value_start, cursor - value_start);
        } else {
            const std::size_t value_start = cursor;
            while (cursor < inner.size() && inner[cursor] != ',') {
                ++cursor;
            }
            value = trim(inner.substr(value_start, cursor - value_start));
        }
        result[key] = value;
        while (cursor < inner.size() && inner[cursor] != ',') {
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
        if (current_section.empty() && key == "format") {
            manifest.format = value == "2" ? 2 : 1;
        } else if (current_section.empty() && key == "name") {
            if (auto parsed = parse_quoted_string(value)) {
                manifest.name = *parsed;
            }
        } else if (current_section.empty() && key == "version") {
            if (auto parsed = parse_quoted_string(value)) {
                manifest.version = *parsed;
            }
        } else if (current_section.empty() && key == "type") {
            if (auto parsed = parse_quoted_string(value)) {
                manifest.type = *parsed;
            }
        } else if (current_section.empty() && key == "sources") {
            manifest.sources = parse_path_array(value);
        } else if (current_section.empty() && (key == "project_references" || key == "references")) {
            manifest.project_references = parse_path_array(value);
        } else if (current_section.empty() && key == "members") {
            manifest.members = parse_path_array(value);
        } else if (current_section == "package") {
            if (key == "id") {
                if (auto parsed = parse_quoted_string(value)) {
                    manifest.package_id = *parsed;
                }
            } else if (key == "description") {
                if (auto parsed = parse_quoted_string(value)) {
                    manifest.description = *parsed;
                }
            } else if (key == "authors") {
                manifest.authors = value;
            } else if (key == "license") {
                if (auto parsed = parse_quoted_string(value)) {
                    manifest.license = *parsed;
                }
            }
        } else if (current_section == "dependencies") {
            CliManifest::Dependency dependency;
            const auto entries = parse_inline_table(value);
            if (const auto found = entries.find("path"); found != entries.end()) {
                if (auto parsed = parse_quoted_string(found->second)) {
                    dependency.path = *parsed;
                }
            }
            if (const auto found = entries.find("id"); found != entries.end()) {
                if (auto parsed = parse_quoted_string(found->second)) {
                    dependency.id = *parsed;
                }
            }
            if (const auto found = entries.find("version"); found != entries.end()) {
                if (auto parsed = parse_quoted_string(found->second)) {
                    dependency.version = *parsed;
                }
            }
            manifest.dependencies[key] = dependency;
        }
    }

    if (manifest.name.empty()) {
        manifest.name = path.stem().string();
    }
    if (manifest.package_id.empty()) {
        manifest.package_id = manifest.name;
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

std::optional<string> json_string_field(const string& object, const string& key) {
    const string needle = "\"" + key + "\"";
    const auto key_pos = object.find(needle);
    if (key_pos == string::npos) {
        return std::nullopt;
    }
    const auto colon = object.find(':', key_pos + needle.size());
    if (colon == string::npos) {
        return std::nullopt;
    }
    auto quote = object.find('"', colon + 1);
    if (quote == string::npos) {
        return std::nullopt;
    }
    ++quote;
    string value;
    while (quote < object.size()) {
        const char ch = object[quote++];
        if (ch == '"') {
            return value;
        }
        if (ch == '\\' && quote < object.size()) {
            value.push_back(object[quote++]);
        } else {
            value.push_back(ch);
        }
    }
    return std::nullopt;
}

struct RegistryPackage {
    string id;
    string version;
    string name;
    string description;
    string authors;
    string license;
    string package_path;
    string project_path;
};

vector<RegistryPackage> read_registry_index(const fs::path& registry, string* error = nullptr) {
    vector<RegistryPackage> packages;
    string text;
    const fs::path index_path = registry / "index.json";
    if (!read_text_file(index_path, text)) {
        if (error != nullptr) {
            *error = "could not read registry index " + index_path.string();
        }
        return packages;
    }
    std::size_t cursor = 0;
    while ((cursor = text.find('{', cursor)) != string::npos) {
        const auto end = text.find('}', cursor);
        if (end == string::npos) {
            if (error != nullptr) {
                *error = "corrupt registry index";
            }
            return {};
        }
        const string object = text.substr(cursor, end - cursor + 1);
        RegistryPackage package;
        package.id = json_string_field(object, "id").value_or("");
        package.version = json_string_field(object, "version").value_or("");
        package.name = json_string_field(object, "name").value_or("");
        package.description = json_string_field(object, "description").value_or("");
        package.authors = json_string_field(object, "authors").value_or("[]");
        package.license = json_string_field(object, "license").value_or("");
        package.package_path = json_string_field(object, "package_path").value_or("");
        package.project_path = json_string_field(object, "project_path").value_or("");
        if (!package.id.empty()) {
            packages.push_back(package);
        }
        cursor = end + 1;
    }
    return packages;
}

bool write_registry_index(const fs::path& registry, const vector<RegistryPackage>& packages) {
    std::ostringstream out;
    out << "{\n  \"packages\": [\n";
    for (std::size_t index = 0; index < packages.size(); ++index) {
        const auto& package = packages[index];
        out << "    {"
            << "\"id\":\"" << escape_json(package.id) << "\","
            << "\"version\":\"" << escape_json(package.version) << "\","
            << "\"name\":\"" << escape_json(package.name) << "\","
            << "\"description\":\"" << escape_json(package.description) << "\","
            << "\"authors\":\"" << escape_json(package.authors) << "\","
            << "\"license\":\"" << escape_json(package.license) << "\","
            << "\"package_path\":\"" << escape_json(package.package_path) << "\","
            << "\"project_path\":\"" << escape_json(package.project_path) << "\""
            << "}";
        if (index + 1 < packages.size()) {
            out << ",";
        }
        out << "\n";
    }
    out << "  ]\n}\n";
    return write_text_file(registry / "index.json", out.str());
}

bool valid_package_id(const string& id) {
    if (id.empty()) {
        return false;
    }
    for (const unsigned char ch : id) {
        if (!(std::isalnum(ch) || ch == '.' || ch == '_' || ch == '-')) {
            return false;
        }
    }
    return true;
}

int compare_versions(const string& left, const string& right) {
    std::istringstream left_stream(left);
    std::istringstream right_stream(right);
    string left_part;
    string right_part;
    while (true) {
        const bool has_left = static_cast<bool>(std::getline(left_stream, left_part, '.'));
        const bool has_right = static_cast<bool>(std::getline(right_stream, right_part, '.'));
        if (!has_left && !has_right) {
            return 0;
        }
        const int left_value = has_left ? std::atoi(left_part.c_str()) : 0;
        const int right_value = has_right ? std::atoi(right_part.c_str()) : 0;
        if (left_value != right_value) {
            return left_value < right_value ? -1 : 1;
        }
    }
}

vector<fs::path> package_files_for_project(const fs::path& project) {
    vector<fs::path> files;
    files.push_back(project);
    for (const auto& entry : fs::directory_iterator(project.parent_path())) {
        if (entry.is_regular_file() &&
            (entry.path().extension() == ".hy" || entry.path().extension() == ".hyproj")) {
            files.push_back(entry.path());
        }
    }
    std::sort(files.begin(), files.end());
    files.erase(std::unique(files.begin(), files.end()), files.end());
    return files;
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
    if (argc < 3) {
        std::cerr << "usage: hy package pack <target> [-o output]\n";
        std::cerr << "   or: hy package add <target.hyproj> <path>\n";
        std::cerr << "   or: hy package init-registry <path>\n";
        std::cerr << "   or: hy package publish <project.hyproj> --registry <path>\n";
        std::cerr << "   or: hy package search <query> --registry <path>\n";
        std::cerr << "   or: hy package install <target.hyproj> <package-id> [--version <version>] --registry <path>\n";
        return 1;
    }
    const string command = argv[2];
    if (command == "pack") {
        if (argc < 4) {
            std::cerr << "usage: hy package pack <target> [-o output]\n";
            return 1;
        }
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

        vector<fs::path> files = target.extension() == ".hyproj" ? package_files_for_project(target) : vector<fs::path>{target};

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

    if (command == "init-registry") {
        if (argc < 4) {
            std::cerr << "usage: hy package init-registry <path>\n";
            return 1;
        }
        const fs::path registry = argv[3];
        fs::create_directories(registry / "packages");
        if (!fs::exists(registry / "index.json") && !write_registry_index(registry, {})) {
            std::cerr << "could not write registry index\n";
            return 1;
        }
        std::cout << (registry / "index.json").string() << "\n";
        return 0;
    }

    if (command == "publish") {
        if (argc < 6) {
            std::cerr << "usage: hy package publish <project.hyproj> --registry <path>\n";
            return 1;
        }
        const fs::path project = argv[3];
        fs::path registry;
        for (int index = 4; index < argc; ++index) {
            const string argument = argv[index];
            if (argument == "--registry" && index + 1 < argc) {
                registry = argv[++index];
            } else {
                std::cerr << "unknown argument: " << argument << "\n";
                return 1;
            }
        }
        if (registry.empty() || !fs::exists(registry / "index.json")) {
            std::cerr << "missing registry index; run hy package init-registry first\n";
            return 1;
        }
        const auto manifest = load_cli_manifest(project);
        if (!manifest.has_value()) {
            std::cerr << "could not read " << project << "\n";
            return 1;
        }
        if (!valid_package_id(manifest->package_id)) {
            std::cerr << "invalid package id: " << manifest->package_id << "\n";
            return 1;
        }
        if (manifest->description.empty() || manifest->license.empty() || manifest->authors == "[]") {
            std::cerr << "package metadata is incomplete\n";
            return 1;
        }
        string index_error;
        auto packages = read_registry_index(registry, &index_error);
        if (!index_error.empty()) {
            std::cerr << index_error << "\n";
            return 1;
        }
        for (const auto& package : packages) {
            if (package.id == manifest->package_id && package.version == manifest->version) {
                std::cerr << "package already exists: " << package.id << " " << package.version << "\n";
                return 1;
            }
        }
        const fs::path package_dir = registry / "packages" / manifest->package_id / manifest->version;
        const fs::path source_dir = package_dir / "src";
        fs::create_directories(source_dir);
        for (const auto& file : package_files_for_project(project)) {
            fs::copy_file(file, source_dir / file.filename(), fs::copy_options::overwrite_existing);
        }
        const fs::path package_path = package_dir / (manifest->package_id + "-" + manifest->version + ".hypkg");
        vector<fs::path> files = package_files_for_project(project);
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
        if (!write_text_file(package_path, archive.str())) {
            std::cerr << "could not write package\n";
            return 1;
        }
        RegistryPackage package;
        package.id = manifest->package_id;
        package.version = manifest->version;
        package.name = manifest->name;
        package.description = manifest->description;
        package.authors = manifest->authors;
        package.license = manifest->license;
        package.package_path = fs::relative(package_path, registry).string();
        package.project_path = fs::relative(source_dir / project.filename(), registry).string();
        packages.push_back(package);
        std::sort(packages.begin(), packages.end(), [](const auto& left, const auto& right) {
            if (left.id != right.id) {
                return left.id < right.id;
            }
            return compare_versions(left.version, right.version) < 0;
        });
        if (!write_registry_index(registry, packages)) {
            std::cerr << "could not update registry index\n";
            return 1;
        }
        std::cout << package_path.string() << "\n";
        return 0;
    }

    if (command == "search") {
        if (argc < 6) {
            std::cerr << "usage: hy package search <query> --registry <path>\n";
            return 1;
        }
        const string query = argv[3];
        fs::path registry;
        for (int index = 4; index < argc; ++index) {
            const string argument = argv[index];
            if (argument == "--registry" && index + 1 < argc) {
                registry = argv[++index];
            } else {
                std::cerr << "unknown argument: " << argument << "\n";
                return 1;
            }
        }
        string index_error;
        const auto packages = read_registry_index(registry, &index_error);
        if (!index_error.empty()) {
            std::cerr << index_error << "\n";
            return 1;
        }
        for (const auto& package : packages) {
            if (package.id.find(query) != string::npos ||
                package.name.find(query) != string::npos ||
                package.description.find(query) != string::npos) {
                std::cout << package.id << " " << package.version << " " << package.description << "\n";
            }
        }
        return 0;
    }

    if (command == "install") {
        if (argc < 7) {
            std::cerr << "usage: hy package install <target.hyproj> <package-id> [--version <version>] --registry <path>\n";
            return 1;
        }
        const fs::path target = argv[3];
        const string package_id = argv[4];
        string requested_version;
        fs::path registry;
        for (int index = 5; index < argc; ++index) {
            const string argument = argv[index];
            if (argument == "--version" && index + 1 < argc) {
                requested_version = argv[++index];
            } else if (argument == "--registry" && index + 1 < argc) {
                registry = argv[++index];
            } else {
                std::cerr << "unknown argument: " << argument << "\n";
                return 1;
            }
        }
        string index_error;
        const auto packages = read_registry_index(registry, &index_error);
        if (!index_error.empty()) {
            std::cerr << index_error << "\n";
            return 1;
        }
        std::optional<RegistryPackage> selected;
        for (const auto& package : packages) {
            if (package.id != package_id) {
                continue;
            }
            if (!requested_version.empty() && package.version != requested_version) {
                continue;
            }
            if (!selected.has_value() || compare_versions(selected->version, package.version) < 0) {
                selected = package;
            }
        }
        if (!selected.has_value()) {
            std::cerr << "package not found: " << package_id << "\n";
            return 1;
        }
        if (!fs::exists(registry / selected->project_path)) {
            std::cerr << "package project missing from registry: " << selected->project_path << "\n";
            return 1;
        }
        string contents;
        if (!read_text_file(target, contents)) {
            std::cerr << "could not read " << target << "\n";
            return 1;
        }
        if (contents.find("format = 2") == string::npos) {
            std::cerr << "hy package install only supports v2 manifests\n";
            return 1;
        }
        if (contents.find("[dependencies]") == string::npos) {
            contents += "\n[dependencies]\n";
        }
        const string relative_project = fs::relative(registry / selected->project_path, target.parent_path()).string();
        contents += selected->id + " = { id = \"" + selected->id + "\", version = \"" + selected->version +
                    "\", path = \"" + relative_project + "\" }\n";
        contents = format_hyproj_v2(contents);
        if (!write_text_file(target, contents)) {
            std::cerr << "could not write " << target << "\n";
            return 1;
        }
        std::cout << selected->id << " " << selected->version << "\n";
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

std::optional<int> json_int_field(const string& object, const string& key) {
    const string needle = "\"" + key + "\"";
    const auto key_pos = object.find(needle);
    if (key_pos == string::npos) {
        return std::nullopt;
    }
    const auto colon = object.find(':', key_pos + needle.size());
    if (colon == string::npos) {
        return std::nullopt;
    }
    std::size_t cursor = colon + 1;
    while (cursor < object.size() && std::isspace(static_cast<unsigned char>(object[cursor]))) {
        ++cursor;
    }
    const std::size_t start = cursor;
    while (cursor < object.size() && std::isdigit(static_cast<unsigned char>(object[cursor]))) {
        ++cursor;
    }
    if (start == cursor) {
        return std::nullopt;
    }
    return std::atoi(object.substr(start, cursor - start).c_str());
}

string uri_to_path(string uri) {
    const string prefix = "file://";
    if (starts_with(uri, prefix)) {
        uri = uri.substr(prefix.size());
    }
    return uri;
}

void write_lsp_message(const string& payload) {
    std::cout << "Content-Length: " << payload.size() << "\r\n\r\n" << payload;
    std::cout.flush();
}

string lsp_response(int id, const string& result) {
    std::ostringstream out;
    out << "{\"jsonrpc\":\"2.0\",\"id\":" << id << ",\"result\":" << result << "}";
    return out.str();
}

string diagnostics_json_for_path(const fs::path& path) {
    hylang::CheckOptions options;
    options.input_path = path;
    const auto result = hylang::check_target(options);
    std::ostringstream out;
    out << "[";
    bool wrote = false;
    for (const auto& diagnostic : result.diagnostics) {
        if (diagnostic.file != path && !diagnostic.file.empty()) {
            continue;
        }
        if (wrote) {
            out << ",";
        }
        wrote = true;
        const int line = std::max(0, diagnostic.line - 1);
        const int column = std::max(0, diagnostic.column - 1);
        out << "{\"range\":{\"start\":{\"line\":" << line << ",\"character\":" << column
            << "},\"end\":{\"line\":" << line << ",\"character\":" << (column + 1)
            << "}},\"severity\":" << (diagnostic.is_warning ? 2 : 1)
            << ",\"source\":\"hylang\",\"message\":\"" << escape_json(diagnostic.message) << "\"}";
    }
    out << "]";
    return out.str();
}

string symbol_kind_for_line(const string& trimmed) {
    if (trimmed.find(" class ") != string::npos || starts_with(trimmed, "class ") || starts_with(trimmed, "public class ")) {
        return "5";
    }
    if (trimmed.find(" struct ") != string::npos || starts_with(trimmed, "struct ") || starts_with(trimmed, "public struct ")) {
        return "23";
    }
    if (trimmed.find(" interface ") != string::npos || starts_with(trimmed, "interface ") || starts_with(trimmed, "public interface ")) {
        return "11";
    }
    if (trimmed.find(" enum ") != string::npos || starts_with(trimmed, "enum ") || starts_with(trimmed, "public enum ")) {
        return "10";
    }
    if (trimmed.find('(') != string::npos && trimmed.find(')') != string::npos) {
        return "6";
    }
    return "8";
}

string declaration_name_from_line(string trimmed) {
    const auto paren = trimmed.find('(');
    if (paren != string::npos) {
        trimmed = trim(trimmed.substr(0, paren));
    }
    const auto brace = trimmed.find('{');
    if (brace != string::npos) {
        trimmed = trim(trimmed.substr(0, brace));
    }
    std::istringstream input(trimmed);
    vector<string> parts;
    string part;
    while (input >> part) {
        if (part == "public" || part == "private" || part == "internal" || part == "protected" ||
            part == "static" || part == "virtual" || part == "override") {
            continue;
        }
        parts.push_back(part);
    }
    if (parts.empty()) {
        return "";
    }
    if ((parts[0] == "class" || parts[0] == "struct" || parts[0] == "interface" || parts[0] == "enum") && parts.size() > 1) {
        return parts[1];
    }
    return parts.back();
}

string document_symbols_json(const string& text) {
    std::ostringstream out;
    out << "[";
    std::istringstream input(text);
    string line;
    int line_number = 0;
    bool wrote = false;
    while (std::getline(input, line)) {
        const string trimmed = trim(line);
        const bool declaration =
            trimmed.find("class ") != string::npos ||
            trimmed.find("struct ") != string::npos ||
            trimmed.find("interface ") != string::npos ||
            trimmed.find("enum ") != string::npos ||
            (trimmed.find('(') != string::npos && trimmed.find(')') != string::npos && trimmed.find("if ") == string::npos &&
             trimmed.find("while ") == string::npos && trimmed.find("for ") == string::npos);
        if (declaration) {
            const string name = declaration_name_from_line(trimmed);
            if (!name.empty()) {
                if (wrote) {
                    out << ",";
                }
                wrote = true;
                out << "{\"name\":\"" << escape_json(name) << "\",\"kind\":" << symbol_kind_for_line(trimmed)
                    << ",\"range\":{\"start\":{\"line\":" << line_number << ",\"character\":0},\"end\":{\"line\":"
                    << line_number << ",\"character\":" << line.size()
                    << "}},\"selectionRange\":{\"start\":{\"line\":" << line_number
                    << ",\"character\":0},\"end\":{\"line\":" << line_number << ",\"character\":" << line.size()
                    << "}}}";
            }
        }
        ++line_number;
    }
    out << "]";
    return out.str();
}

string hover_json(const string& text, int target_line) {
    std::istringstream input(text);
    string line;
    int line_number = 0;
    while (std::getline(input, line)) {
        if (line_number == target_line) {
            const string trimmed = trim(line);
            const string name = declaration_name_from_line(trimmed);
            const string value = name.empty() ? trimmed : name + ": " + trimmed;
            return "{\"contents\":{\"kind\":\"markdown\",\"value\":\"`" + escape_json(value) + "`\"}}";
        }
        ++line_number;
    }
    return "null";
}

int handle_lsp() {
    std::unordered_map<string, string> documents;
    string header;
    while (std::getline(std::cin, header)) {
        if (!header.empty() && header.back() == '\r') {
            header.pop_back();
        }
        if (!starts_with(header, "Content-Length:")) {
            continue;
        }
        const int length = std::atoi(trim(header.substr(string("Content-Length:").size())).c_str());
        std::getline(std::cin, header);
        string payload(static_cast<std::size_t>(length), '\0');
        std::cin.read(payload.data(), length);
        const auto id = json_int_field(payload, "id");
        const auto method = json_string_field(payload, "method").value_or("");
        if (method == "initialize") {
            if (id.has_value()) {
                write_lsp_message(lsp_response(*id,
                    "{\"capabilities\":{\"textDocumentSync\":1,\"documentSymbolProvider\":true,\"hoverProvider\":true,\"documentFormattingProvider\":true}}"));
            }
        } else if (method == "shutdown") {
            if (id.has_value()) {
                write_lsp_message(lsp_response(*id, "null"));
            }
        } else if (method == "textDocument/didOpen" || method == "textDocument/didChange") {
            const auto uri = json_string_field(payload, "uri");
            const auto text = json_string_field(payload, "text");
            if (uri.has_value() && text.has_value()) {
                documents[*uri] = *text;
                const fs::path path = uri_to_path(*uri);
                write_lsp_message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"" +
                                  escape_json(*uri) + "\",\"diagnostics\":" + diagnostics_json_for_path(path) + "}}");
            }
        } else if (method == "textDocument/didClose") {
            if (const auto uri = json_string_field(payload, "uri")) {
                documents.erase(*uri);
                write_lsp_message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"" +
                                  escape_json(*uri) + "\",\"diagnostics\":[]}}");
            }
        } else if (method == "textDocument/documentSymbol") {
            const auto uri = json_string_field(payload, "uri");
            string text;
            if (uri.has_value()) {
                const auto found = documents.find(*uri);
                if (found != documents.end()) {
                    text = found->second;
                } else {
                    read_text_file(uri_to_path(*uri), text);
                }
            }
            if (id.has_value()) {
                write_lsp_message(lsp_response(*id, document_symbols_json(text)));
            }
        } else if (method == "textDocument/hover") {
            const auto uri = json_string_field(payload, "uri");
            const int line = json_int_field(payload, "line").value_or(0);
            string text;
            if (uri.has_value()) {
                const auto found = documents.find(*uri);
                if (found != documents.end()) {
                    text = found->second;
                } else {
                    read_text_file(uri_to_path(*uri), text);
                }
            }
            if (id.has_value()) {
                write_lsp_message(lsp_response(*id, hover_json(text, line)));
            }
        } else if (method == "textDocument/formatting") {
            const auto uri = json_string_field(payload, "uri");
            string text;
            if (uri.has_value()) {
                const auto found = documents.find(*uri);
                if (found != documents.end()) {
                    text = found->second;
                } else {
                    read_text_file(uri_to_path(*uri), text);
                }
            }
            const string formatted = format_hy_source(text);
            const string escaped = escape_json(formatted);
            if (id.has_value()) {
                write_lsp_message(lsp_response(*id,
                    "[{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":999999,\"character\":0}},\"newText\":\"" +
                        escaped + "\"}]"));
            }
        } else if (method == "exit") {
            return 0;
        } else if (id.has_value()) {
            write_lsp_message(lsp_response(*id, "null"));
        }
    }
    return 0;
}

void print_usage() {
    std::cerr << "usage:\n";
    std::cerr << "  hy new app|lib|tool|test|workspace <name>\n";
    std::cerr << "  hy build <file.hy|project.hyproj> [--target exe|lib] [-o output] [--debug]\n";
    std::cerr << "  hy run <file.hy|project.hyproj> [-- args...]\n";
    std::cerr << "  hy test [project.hyproj]\n";
    std::cerr << "  hy fmt <path...> [--check]\n";
    std::cerr << "  hy check <file.hy|project.hyproj> [--json]\n";
    std::cerr << "  hy lsp\n";
    std::cerr << "  hy package pack <target> [-o output]\n";
    std::cerr << "  hy package add <target.hyproj> <path>\n";
    std::cerr << "  hy package init-registry|publish|search|install ...\n";
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
    if (command == "lsp") {
        return handle_lsp();
    }

    print_usage();
    return 1;
}
