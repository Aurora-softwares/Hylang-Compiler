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
#else
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
        if (log_) std::cerr << "Building " << input << '\n';
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
            if (progress_) std::cerr << "100% " << message << '\n';
            else if (log_) std::cerr << message << '\n';
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
            std::cerr << '[' << std::string(60, '#') << "] 100% total\n";
        }
    }

private:
    void draw() {
        static const char* frames[] = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"};
        if (terminal_) std::cerr << "\r\x1b[2K";
        if (spinner_) std::cerr << frames[frame_ % 10] << ' ';
        if (progress_) {
            const std::size_t overall_percent = total_ == 0 ? 0 : completed_ * 100 / total_;
            const std::size_t filled = overall_percent * 60 / 100;
            std::cerr << '[' << std::string(filled, '#') << std::string(60 - filled, '-')
                      << "] " << overall_percent << "% total | " << action_percent_ << "% ";
        }
        if (terminal_) std::cerr << message_ << std::flush;
        else std::cerr << message_;
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
