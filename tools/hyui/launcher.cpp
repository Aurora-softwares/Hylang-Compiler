// A packaged app's OS-native entry point. No Qt or Hydrogen installation is
// needed to start it; the private runtime is selected before loading Qt.
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
#else
#include <cstdlib>
#include <unistd.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
#endif

namespace fs = std::filesystem;

#ifdef _WIN32
static std::wstring quote(const std::wstring& text) {
    std::wstring result = L"\"";
    unsigned slashes = 0;
    for (wchar_t ch : text) {
        if (ch == L'\\') { ++slashes; continue; }
        if (ch == L'\"') { result.append(slashes * 2 + 1, L'\\'); }
        else { result.append(slashes, L'\\'); }
        slashes = 0;
        result += ch;
    }
    result.append(slashes * 2, L'\\');
    return result + L'\"';
}
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    std::wstring path(32768, L'\0');
    DWORD length = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
    if (length == 0 || length >= path.size()) { return 1; }
    path.resize(length);
    fs::path runtime = fs::path(path + L".runtime");
    fs::path host = runtime / L"hyui.exe";
    if (!fs::exists(host)) {
        MessageBoxW(nullptr, L"Keep the application's .runtime folder beside its executable.", L"Hydrogen application", MB_ICONERROR);
        return 1;
    }
    // DLL lookup is configured only for this application process and its child.
    std::wstring oldPath(32768, L'\0');
    DWORD oldLength = GetEnvironmentVariableW(L"PATH", oldPath.data(), static_cast<DWORD>(oldPath.size()));
    oldPath.resize(oldLength < oldPath.size() ? oldLength : 0);
    SetEnvironmentVariableW(L"PATH", (runtime.wstring() + L";" + oldPath).c_str());
    SetEnvironmentVariableW(L"QT_PLUGIN_PATH", (runtime / L"plugins").c_str());
    SetEnvironmentVariableW(L"QML_IMPORT_PATH", (runtime / L"qml").c_str());
    std::wstring command = quote(host.wstring()) + L" --bundle " + quote((runtime / L"app").wstring());
    int count = 0;
    LPWSTR* args = CommandLineToArgvW(GetCommandLineW(), &count);
    if (args) {
        for (int i = 1; i < count; ++i) { command += L" " + quote(args[i]); }
        LocalFree(args);
    }
    STARTUPINFOW startup{}; startup.cb = sizeof(startup);
    PROCESS_INFORMATION child{};
    if (!CreateProcessW(host.c_str(), command.data(), nullptr, nullptr, FALSE, 0, nullptr,
                        nullptr, &startup, &child)) {
        MessageBoxW(nullptr, L"The bundled desktop runtime could not be started.", L"Hydrogen application", MB_ICONERROR);
        return 1;
    }
    CloseHandle(child.hThread);
    WaitForSingleObject(child.hProcess, INFINITE);
    DWORD status = 1; GetExitCodeProcess(child.hProcess, &status); CloseHandle(child.hProcess);
    return static_cast<int>(status);
}
#else
int main(int argc, char** argv) {
    fs::path self;
#ifdef __APPLE__
    uint32_t length = 0;
    _NSGetExecutablePath(nullptr, &length);
    std::string path(length, '\0');
    if (_NSGetExecutablePath(path.data(), &length) != 0) { return 1; }
    self = fs::canonical(path.c_str());
    const fs::path contents = self.parent_path().parent_path();
    const fs::path runtime = contents;
    const fs::path host = contents / "MacOS/hyui";
    const fs::path app = contents / "Resources/app";
    setenv("QT_PLUGIN_PATH", (contents / "PlugIns").c_str(), 1);
    setenv("QML_IMPORT_PATH", (contents / "Resources/qml").c_str(), 1);
#else
    std::string path(65536, '\0');
    ssize_t length = readlink("/proc/self/exe", path.data(), path.size() - 1);
    if (length < 0) { std::cerr << "cannot locate the application executable\n"; return 1; }
    path.resize(static_cast<size_t>(length));
    self = path;
    const fs::path runtime = path + ".runtime";
    const fs::path host = runtime / "hyui";
    const fs::path app = runtime / "app";
    // Use only the bundled Qt modules. GPU drivers and the platform's base C
    // runtime remain system dependencies, as for other Linux desktop apps.
    setenv("LD_LIBRARY_PATH", (runtime / "lib").c_str(), 1);
    setenv("QT_PLUGIN_PATH", (runtime / "plugins").c_str(), 1);
    setenv("QML_IMPORT_PATH", (runtime / "qml").c_str(), 1);
#endif
    if (!fs::exists(host)) { std::cerr << "Keep the application's runtime beside its executable.\n"; return 1; }
    std::vector<std::string> arguments = {host.string(), "--bundle", app.string()};
    for (int i = 1; i < argc; ++i) { arguments.emplace_back(argv[i]); }
    std::vector<char*> pointers;
    for (auto& arg : arguments) { pointers.push_back(arg.data()); }
    pointers.push_back(nullptr);
    // Assets use absolute bundle paths. Preserve the caller's working directory
    // so explicit relative output paths retain their ordinary meaning.
    execv(host.c_str(), pointers.data());
    std::cerr << "cannot start the bundled desktop runtime\n";
    return 1;
}
#endif
