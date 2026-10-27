#pragma once

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdio>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>

#ifdef _WIN32
#include <io.h>
#include <windows.h>
#else
#include <sys/ioctl.h>
#include <unistd.h>
#endif

// CLI-only presentation. Each reported action owns one terminal line.
class BuildDisplay {
public:
    BuildDisplay(bool hide_progress, bool hide_spinner, bool hide_log)
        : progress_(!hide_progress), spinner_(!hide_spinner), log_(!hide_log) {
#ifdef _WIN32
        terminal_ = _isatty(_fileno(stderr)) != 0;
#else
        terminal_ = isatty(fileno(stderr)) != 0;
#endif
    }

    ~BuildDisplay() { finish(); }

    void begin(const std::string& input) {
        if (log_) std::cerr << fit("Building " + input) << '\n';
        if (terminal_ && spinner_) {
            running_ = true;
            worker_ = std::thread([this] {
                while (true) {
                    {
                        std::lock_guard<std::mutex> lock(mutex_);
                        if (!running_) break;
                        if (active_) {
                            draw();
                            ++frame_;
                        }
                    }
                    std::this_thread::sleep_for(std::chrono::milliseconds(90));
                }
            });
        }
    }

    void update(std::size_t completed, std::size_t total, const std::string& message) {
        std::lock_guard<std::mutex> lock(mutex_);
        const bool finished_action = completed > completed_;
        const bool new_action = !active_ || message != message_;
        completed_ = completed;
        total_ = total;
        message_ = message;
        if (terminal_ && active_ && (progress_ || spinner_)) std::cerr << "\r\x1b[2K";
        if (finished_action) {
            if (progress_) std::cerr << fit("100% " + message) << '\n';
            else if (log_) std::cerr << fit(message) << '\n';
            active_ = false;
        } else {
            active_ = true;
            if (new_action) action_percent_ = 0;
            if (terminal_ && (progress_ || spinner_)) draw();
        }
    }

    void action_progress(std::size_t percent) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!active_) return;
        action_percent_ = std::min<std::size_t>(99, percent);
        if (terminal_ && (progress_ || spinner_)) draw();
    }

    void finish() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (finished_) return;
            finished_ = true;
            running_ = false;
        }
        if (worker_.joinable()) worker_.join();
        if (terminal_ && active_ && (progress_ || spinner_)) {
            std::cerr << "\r\x1b[2K";
            std::cerr << std::flush;
        }
        if (terminal_ && progress_ && total_ != 0 && completed_ >= total_) {
            const std::size_t width = columns();
            const std::size_t bar_width = width > 14 ? std::min<std::size_t>(60, width - 14) : 0;
            const std::string result = bar_width > 0
                ? "[" + std::string(bar_width, '#') + "] 100% total" : "100% total";
            std::cerr << fit(result) << '\n';
        }
    }

private:
    std::size_t columns() const {
        if (!terminal_) return 0;
#ifdef _WIN32
        CONSOLE_SCREEN_BUFFER_INFO info{};
        const HANDLE handle = GetStdHandle(STD_ERROR_HANDLE);
        if (handle != INVALID_HANDLE_VALUE && GetConsoleScreenBufferInfo(handle, &info))
            return static_cast<std::size_t>(info.srWindow.Right - info.srWindow.Left + 1);
#else
        winsize size{};
        if (ioctl(fileno(stderr), TIOCGWINSZ, &size) == 0 && size.ws_col > 0)
            return size.ws_col;
#endif
        return 0;
    }

    std::string fit(std::string line) const {
        if (!terminal_) return line;
        const std::size_t width = columns();
        if (width == 0) return line;
        const std::size_t limit = width - 1; // Avoid the terminal's last-column wrap.
        for (char& ch : line) if (ch == '\n' || ch == '\r' || ch == '\t') ch = ' ';
        if (line.size() <= limit) return line;
        if (limit <= 3) return std::string(limit, '.');
        std::size_t end = limit - 3;
        while (end > 0 && end < line.size() &&
               (static_cast<unsigned char>(line[end]) & 0xc0) == 0x80) --end;
        return line.substr(0, end) + "...";
    }

    void draw() {
        static const char* frames[] = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"};
        if (terminal_) std::cerr << "\r\x1b[2K";
        std::string line;
        if (spinner_) line = std::string(frames[frame_ % 10]) + ' ';
        if (progress_) {
            const std::size_t overall_percent = total_ == 0 ? 0 : completed_ * 100 / total_;
            const std::string suffix = "] " + std::to_string(overall_percent) + "% total | " +
                                       std::to_string(action_percent_) + "% ";
            const std::size_t width = columns();
            const std::size_t reserve = width / 3;
            const std::size_t bar_width = width > line.size() + suffix.size() + reserve + 2
                ? std::min<std::size_t>(60, width - line.size() - suffix.size() - reserve - 2) : 0;
            if (bar_width >= 8) {
                const std::size_t filled = overall_percent * bar_width / 100;
                line += '[' + std::string(filled, '#') + std::string(bar_width - filled, '-') + suffix;
            } else if (width > 16) {
                line += std::to_string(overall_percent) + "% | " + std::to_string(action_percent_) + "% ";
            }
        }
        line += message_;
        std::cerr << fit(line) << std::flush;
    }

    bool progress_;
    bool spinner_;
    bool log_;
    bool terminal_ = false;
    bool running_ = false;
    bool finished_ = false;
    bool active_ = false;
    std::size_t action_percent_ = 0;
    std::size_t completed_ = 0;
    std::size_t total_ = 0;
    std::size_t frame_ = 0;
    std::string message_;
    std::mutex mutex_;
    std::thread worker_;
};
