#!/usr/bin/env bash

# ==============================================================================
# Hydrogen Compiler Bootstrap
#
# Builds the C++ Stage 0 compiler, then bootstraps the self-hosting Hydrogen
# compiler through stages 1, 2, and 3 before verifying reproducibility.
#
# Run this script from the root of the Hydrogen compiler repository:
#
#   ./bootstrap.sh
#
# ==============================================================================

set -Eeuo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# The project is ALWAYS the directory the user ran the script from.
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

BUILD_DIR="$PROJECT_DIR/build"
BOOTSTRAP_BUILD_DIR="$BUILD_DIR/bootstrap"
SELF_HOST_DIR="$BUILD_DIR/self_hosting"

STAGE0="$BOOTSTRAP_BUILD_DIR/hy"
BOOTSTRAP="$BOOTSTRAP_BUILD_DIR/hydrogen-bootstrap"

# Linux self-hosting
LINUX_DIR="$SELF_HOST_DIR/linux"

LINUX_PROJECT_FILE="$PROJECT_DIR/src/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj"
#LINUX_PROJECT_FILE="$PROJECT_DIR/src/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.Linux.hyproj"

LINUX_STAGE1="$LINUX_DIR/hydrogen-stage1"
LINUX_STAGE2="$LINUX_DIR/hydrogen-stage2"
LINUX_STAGE3="$LINUX_DIR/hydrogen-stage3"

LINUX_STAGE1_PENDING="$LINUX_DIR/hydrogen-stage1.pending"
LINUX_STAGE2_PENDING="$LINUX_DIR/hydrogen-stage2.pending"
LINUX_STAGE3_PENDING="$LINUX_DIR/hydrogen-stage3.pending"

# Windows self-hosting
WINDOWS_DIR="$SELF_HOST_DIR/windows"

WINDOWS_PROJECT_FILE="$PROJECT_DIR/src/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.Windows.hyproj"

WINDOWS_STAGE1="$WINDOWS_DIR/hydrogen-stage1.exe"
WINDOWS_STAGE2="$WINDOWS_DIR/hydrogen-stage2.exe"
WINDOWS_STAGE3="$WINDOWS_DIR/hydrogen-stage3.exe"

WINDOWS_STAGE1_PENDING="$WINDOWS_DIR/hydrogen-stage1.pending.exe"
WINDOWS_STAGE2_PENDING="$WINDOWS_DIR/hydrogen-stage2.pending.exe"
WINDOWS_STAGE3_PENDING="$WINDOWS_DIR/hydrogen-stage3.pending.exe"

# Mac self-hosting
MACOS_DIR="$SELF_HOST_DIR/mac"

MACOS_PROJECT_FILE="$PROJECT_DIR/src/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.MacOS.hyproj"

MACOS_STAGE1="$MACOS_DIR/hydrogen-stage1"
MACOS_STAGE2="$MACOS_DIR/hydrogen-stage2"
MACOS_STAGE3="$MACOS_DIR/hydrogen-stage3"

MACOS_STAGE1_PENDING="$MACOS_DIR/hydrogen-stage1.pending"
MACOS_STAGE2_PENDING="$MACOS_DIR/hydrogen-stage2.pending"
MACOS_STAGE3_PENDING="$MACOS_DIR/hydrogen-stage3.pending"

LOG_FILE="$BUILD_DIR/bootstrap.log"
STEP_LOG_DIR="$BUILD_DIR/bootstrap-logs"

TOTAL_STEPS=26
CURRENT_STEP=0
CURRENT_MESSAGE="Starting..."

# Braille spinner frames.
SPINNER=(
    "⠋"
    "⠙"
    "⠹"
    "⠸"
    "⠼"
    "⠴"
    "⠦"
    "⠧"
    "⠇"
    "⠏"
)

# ------------------------------------------------------------------------------
# Colours
# ------------------------------------------------------------------------------

if [[ -t 1 ]]; then
    RESET="\033[0m"
    BOLD="\033[1m"

    RED="\033[31m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    BLUE="\033[34m"
    CYAN="\033[36m"
    GREY="\033[90m"
else
    RESET=""
    BOLD=""

    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    GREY=""
fi

# ------------------------------------------------------------------------------
# Utility functions
# ------------------------------------------------------------------------------

info() {
    printf "${BLUE}ℹ${RESET} %s\n" "$*"
}

success() {
    printf "${GREEN}✓${RESET} %s\n" "$*"
}

warning() {
    printf "${YELLOW}⚠${RESET} %s\n" "$*"
}

error() {
    printf "${RED}✗${RESET} %s\n" "$*" >&2
}

clear_progress_line() {
    # Clear the whole current terminal line.
    printf "\r\033[2K"
}

die() {
    clear_progress_line
    error "$*"

    if [[ -f "$LOG_FILE" ]]; then
        printf "\n"
        printf "${GREY}Last 20 lines of the build log:${RESET}\n"
        printf "${GREY}----------------------------------------${RESET}\n"
        tail -n 20 "$LOG_FILE" >&2 || true
        printf "${GREY}----------------------------------------${RESET}\n"
        printf "Full log: %s\n" "$LOG_FILE"
    fi

    exit 1
}

# ------------------------------------------------------------------------------
# Progress bar
# ------------------------------------------------------------------------------

draw_progress() {
    local message="$1"
    local spinner="${2:- }"

    local width=30
    local percent=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
    local filled=$(( CURRENT_STEP * width / TOTAL_STEPS ))
    local empty=$(( width - filled ))

    local bar_filled=""
    local bar_empty=""

    printf -v bar_filled "%${filled}s" ""
    printf -v bar_empty "%${empty}s" ""

    bar_filled="${bar_filled// /#}"
    bar_empty="${bar_empty// /-}"

    # Return to the start of the line and clear the entire line first.
    printf "\r\033[2K"

    printf "${CYAN}%b [%s%s]${RESET} %3d%%  %s" \
        "$spinner" \
        "$bar_filled" \
        "$bar_empty" \
        "$percent" \
        "$message"
}

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    CURRENT_MESSAGE="$1"

    draw_progress "$CURRENT_MESSAGE" " "
}

# ------------------------------------------------------------------------------
# Command runner with spinner
# ------------------------------------------------------------------------------

run() {
    printf "\n\n==> %s\n" "$*" >> "$LOG_FILE"

    # Start command in the background and send output to the log.
    "$@" >> "$LOG_FILE" 2>&1 &

    local command_pid=$!
    local spinner_index=0

    # Animate while command is running.
    while kill -0 "$command_pid" 2>/dev/null; do
        draw_progress "$CURRENT_MESSAGE" "${SPINNER[$spinner_index]}"

        spinner_index=$(( (spinner_index + 1) % ${#SPINNER[@]} ))

        sleep 0.08
    done

    # Collect the actual exit code.
    local exit_code=0

    wait "$command_pid" || exit_code=$?

    if (( exit_code != 0 )); then
        clear_progress_line

        die "Command failed:
  $*

Exit code: $exit_code"
    fi

    # Leave the completed operation visible with a tick.
    draw_progress "$CURRENT_MESSAGE" "${GREEN}✓${RESET}"
}

run_test() {
    printf "\n\n==> %s\n" "$*" >> "$LOG_FILE"

    "$@" >> "$LOG_FILE" 2>&1 &

    local command_pid=$!
    local spinner_index=0

    while kill -0 "$command_pid" 2>/dev/null; do
        draw_progress "$CURRENT_MESSAGE" "${SPINNER[$spinner_index]}"

        spinner_index=$(( (spinner_index + 1) % ${#SPINNER[@]} ))

        sleep 0.08
    done

    local exit_code=0

    wait "$command_pid" || exit_code=$?

    # For compiler sanity checks we accept 0 or 1.
    #
    # Some versions of Hydrogen currently return 1 for --help even
    # though the executable launched correctly and printed its usage.
    if (( exit_code > 1 )); then
        clear_progress_line

        die "Compiler sanity check failed:
  $*

Exit code: $exit_code"
    fi

    draw_progress "$CURRENT_MESSAGE" "${GREEN}✓${RESET}"
}

# ------------------------------------------------------------------------------
# File validation
# ------------------------------------------------------------------------------

require_file() {
    local file="$1"
    local description="$2"

    if [[ ! -f "$file" ]]; then
        die "$description was not found:
  $file"
    fi
}

require_executable() {
    local file="$1"
    local description="$2"

    if [[ ! -f "$file" ]]; then
        die "$description was not created:
  $file"
    fi

    if [[ ! -x "$file" ]]; then
        chmod +x "$file" ||
            die "Could not make $description executable."
    fi
}

# ------------------------------------------------------------------------------
# Error handling
# ------------------------------------------------------------------------------

cleanup() {
    rm -f \
	"$LINUX_STAGE1_PENDING" "$LINUX_STAGE2_PENDING" "$LINUX_STAGE3_PENDING" \
	"$WINDOWS_STAGE1_PENDING" "$WINDOWS_STAGE2_PENDING" "$WINDOWS_STAGE3_PENDING" \
	"$MACOS_STAGE1_PENDING" "$MACOS_STAGE2_PENDING" "$MACOS_STAGE3_PENDING" \
	2>/dev/null || true
}

on_error() {
    local exit_code=$?

    clear_progress_line

    cleanup

    error "Bootstrap failed unexpectedly."

    if [[ -f "$LOG_FILE" ]]; then
        printf "\nSee the full log at:\n  %s\n" "$LOG_FILE"
    fi

    exit "$exit_code"
}

trap on_error ERR
trap cleanup EXIT

# ------------------------------------------------------------------------------
# Dependency handling
# ------------------------------------------------------------------------------

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"

    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"

    elif command -v yum >/dev/null 2>&1; then
        echo "yum"

    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"

    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"

    else
        echo "unknown"
    fi
}

install_dependencies() {
    local package_manager
    package_manager="$(detect_package_manager)"

    printf "\n"

    warning "Some required build tools are missing."

    case "$package_manager" in

        apt)
            info "Detected Debian/Ubuntu."
            info "Installing build-essential and CMake..."

            sudo apt-get update
            sudo apt-get install -y build-essential cmake wine
            ;;

        dnf)
            info "Detected Fedora/RHEL."
            info "Installing GCC, GCC C++, Make and CMake..."

            sudo dnf install -y gcc gcc-c++ make cmake wine 
            ;;

        yum)
            info "Detected yum."
            info "Installing GCC, GCC C++, Make and CMake..."

            sudo yum install -y gcc gcc-c++ make cmake wine 
            ;;

        pacman)
            info "Detected Arch Linux."
            info "Installing base-devel and CMake..."

            sudo pacman -S --needed --noconfirm base-devel cmake wine 
            ;;

        zypper)
            info "Detected openSUSE."
            info "Installing compiler tools and CMake..."

            sudo zypper --non-interactive install gcc gcc-c++ make cmake wine 
            ;;

        *)
            die "Required build tools are missing and your package manager
could not be detected automatically.

Please install:

  • CMake
  • A C++ compiler (GCC or Clang)
  • Make or another CMake-compatible build system

Then run this script again."
            ;;
    esac
}

check_dependencies() {
    local missing=0

    if ! command -v cmake >/dev/null 2>&1; then
        warning "CMake is not installed."
        missing=1
    fi

    if ! command -v c++ >/dev/null 2>&1 &&
       ! command -v g++ >/dev/null 2>&1 &&
       ! command -v clang++ >/dev/null 2>&1; then

        warning "No C++ compiler was found."
        missing=1
    fi

    if (( missing == 1 )); then

        if [[ ! -t 0 ]]; then
            die "Missing build dependencies and no interactive terminal is available."
        fi

        printf "\n"

        read -r -p "Would you like to install the missing dependencies? [Y/n] " answer

        answer="${answer:-Y}"

        if [[ "$answer" =~ ^[Yy]$ ]]; then
            install_dependencies
        else
            die "Cannot continue without the required build dependencies."
        fi
    fi

    # Verify again after attempted installation.
    command -v cmake >/dev/null 2>&1 ||
        die "CMake is still unavailable."

    if ! command -v c++ >/dev/null 2>&1 &&
       ! command -v g++ >/dev/null 2>&1 &&
       ! command -v clang++ >/dev/null 2>&1; then

        die "A C++ compiler is still unavailable."
    fi
}

# ------------------------------------------------------------------------------
# Header
# ------------------------------------------------------------------------------

clear 2>/dev/null || true

printf "${BOLD}${CYAN}"
printf "╔══════════════════════════════════════════════════════╗\n"
printf "║              Hydrogen Compiler Bootstrap             ║\n"
printf "╚══════════════════════════════════════════════════════╝\n"
printf "${RESET}\n"

printf "Project: %s\n\n" "$PROJECT_DIR"

# ------------------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------------------

if [[ ! -f "$PROJECT_DIR/CMakeLists.txt" ]]; then
    die "No CMakeLists.txt was found in the current directory:

  $PROJECT_DIR

This does not appear to be the Hydrogen compiler repository.

Run this script from the root of the Hydrogen project."
fi

require_file "$LINUX_PROJECT_FILE" "Hydrogen self-hosting project"

mkdir -p "$BUILD_DIR"
mkdir -p "$BOOTSTRAP_BUILD_DIR"
mkdir -p "$LINUX_DIR" "$WINDOWS_DIR" "$MACOS_DIR" "$STEP_LOG_DIR"

# Reset log each run.
: > "$LOG_FILE"

info "Checking build requirements..."
check_dependencies
success "Build requirements available."

# ------------------------------------------------------------
# Windows testing environment (Wine)
# ------------------------------------------------------------

WINE=""
TEST_WINDOWS=false
WINDOWS_TEST_REASON="Wine is not installed."
WINDOWS_BUILD_AVAILABLE=false

if command -v wine >/dev/null 2>&1; then
    WINE="$(command -v wine)"
elif command -v wine64 >/dev/null 2>&1; then
    WINE="$(command -v wine64)"
fi

if [[ -n "$WINE" ]]; then
    if "$WINE" --version >> "$LOG_FILE" 2>&1; then
        TEST_WINDOWS=true
        WINDOWS_TEST_REASON=""
        success "Wine is available for Windows testing."
    else
        WINDOWS_TEST_REASON="Wine is installed but failed its version check."
        warning "$WINDOWS_TEST_REASON"
    fi
else
    warning "Wine is unavailable; Windows execution tests will be skipped."
fi

if [[ -f "$WINDOWS_PROJECT_FILE" ]]; then
    WINDOWS_BUILD_AVAILABLE=true
else
    warning "Windows compiler project not found: $WINDOWS_PROJECT_FILE"
fi

mkdir -p "$WINDOWS_DIR"


# ------------------------------------------------------------
# macOS testing environment (Darling)
# ------------------------------------------------------------

DARLING=""
TEST_MACOS=false
MACOS_TEST_REASON="Darling is not installed."
MACOS_BUILD_AVAILABLE=false

if command -v darling >/dev/null 2>&1; then
    DARLING="$(command -v darling)"

    if "$DARLING" shell uname -s 2>> "$LOG_FILE" |
       grep -qx "Darwin"; then

        TEST_MACOS=true
        MACOS_TEST_REASON=""
        success "Darling is available for macOS testing."
    else
        MACOS_TEST_REASON="Darling is installed but failed its startup check."
        warning "$MACOS_TEST_REASON"
    fi
else
    warning "Darling is unavailable; macOS execution tests will be skipped."
fi

if [[ -f "$MACOS_PROJECT_FILE" ]]; then
    MACOS_BUILD_AVAILABLE=true
else
    warning "macOS compiler project not found: $MACOS_PROJECT_FILE"
fi

mkdir -p "$MACOS_DIR"


# Remove stale pending files from previous failed builds.
cleanup

printf "\n"

# ------------------------------------------------------------------------------
# Stage 0
# ------------------------------------------------------------------------------
step "Configuring build..."
run cmake -S "$PROJECT_DIR" -B "$BOOTSTRAP_BUILD_DIR" -DCMAKE_BUILD_TYPE=Release
step "Building C++ Stage 0 compiler..."
run cmake --build "$BOOTSTRAP_BUILD_DIR" --target hy --parallel
require_executable "$STAGE0" "Stage 0 compiler"

## Testing
step "Testing compiler..."
run_test "$STAGE0" --help

# ------------------------------------------------------------------------------
# Bootstrap compiler
# ------------------------------------------------------------------------------
step "Building temporary bootstrap compiler..."
rm -f "$BOOTSTRAP"
run "$STAGE0" build "$LINUX_PROJECT_FILE" -o "$BOOTSTRAP"
require_executable "$BOOTSTRAP" "bootstrap compiler"

## Testing
step "Testing temporary bootstrap compiler..."
run_test "$BOOTSTRAP" --help

# ------------------------------------------------------------------------------
# Cross-platform command and result handling
# ------------------------------------------------------------------------------
# Stage 0 and the temporary bootstrap remain mandatory prerequisites. The three
# target bootstraps are independent; failure in one does not stop another.

declare -A PLATFORM_STATUS=( [Linux]="NOT RUN" [Windows]="NOT RUN" [macOS]="NOT RUN" )
declare -A PLATFORM_REASON=( [Linux]="" [Windows]="" [macOS]="" )
declare -A PRODUCED=()
LAST_FAILURE=""

# A nonfatal alternative to run()/run_test(), with a separate diagnostic log.
# For --help only, status 1 is accepted because Hydrogen has used it for usage.
try_run() {
    local allow_help_one="$1"
    shift
    local safe_name="${CURRENT_MESSAGE//[^[:alnum:]]/_}"
    local command_log="$STEP_LOG_DIR/$(printf '%02d' "$CURRENT_STEP")_${safe_name}.log"
    local code=0
    printf '\n\n==>' >> "$LOG_FILE"
    printf ' %q' "$@" >> "$LOG_FILE"
    printf '\n' >> "$LOG_FILE"

    "$@" > "$command_log" 2>&1 &
    local child_pid=$!
    local spinner_index=0
    while kill -0 "$child_pid" 2>/dev/null; do
        draw_progress "$CURRENT_MESSAGE" "${SPINNER[$spinner_index]}"
        spinner_index=$(( (spinner_index + 1) % ${#SPINNER[@]} ))
        sleep 0.08
    done
    wait "$child_pid" || code=$?
    cat "$command_log" >> "$LOG_FILE"

    if (( code == 0 || (allow_help_one == 1 && code == 1) )); then
        draw_progress "$CURRENT_MESSAGE" "${GREEN}✓${RESET}"
        return 0
    fi

    local diagnostic
    diagnostic="$(grep -v '^[[:space:]]*$' "$command_log" | tail -n 1 || true)"
    diagnostic="${diagnostic//$'\r'/ }"
    LAST_FAILURE="exit code $code"
    if [[ -n "$diagnostic" ]]; then LAST_FAILURE+=": $diagnostic"; fi
    LAST_FAILURE+=" (see $command_log)"
    draw_progress "$CURRENT_MESSAGE" "${RED}✗${RESET}"
    return 1
}

mark_failure() {
    local platform="$1" reason="$2"
    PLATFORM_STATUS["$platform"]="FAILED"
    PLATFORM_REASON["$platform"]="$reason"
	printf '\n'
    warning "$platform: $reason"
    printf '\n[%s] FAILED: %s\n' "$platform" "$reason" >> "$LOG_FILE"
}

# Do not report .o objects, ELF, or PE images as runnable macOS compilers.
check_binary_type() {
    local platform="$1" binary="$2" description
    if [[ ! -s "$binary" ]]; then
        LAST_FAILURE="generated file is missing or empty: $binary"
        return 1
    fi
    if ! command -v file >/dev/null 2>&1; then
        LAST_FAILURE="the 'file' command is required to verify generated binaries"
        return 1
    fi
    if ! description="$(file -b -- "$binary" 2>&1)"; then
        LAST_FAILURE="could not inspect output $binary: $description"
        return 1
    fi
    printf '%s image: %s\n' "$platform" "$description" >> "$LOG_FILE"
    case "$platform" in
        Linux)
            [[ "$description" == *ELF* && "$description" == *x86-64* ]] ;;
        Windows)
            [[ "$description" == *PE32+* && "$description" == *x86-64* ]] ;;
        macOS)
            [[ "$description" == *Mach-O* && "$description" == *x86_64* && "$description" == *executable* ]] ;;
    esac && return 0
    LAST_FAILURE="unexpected image type: $description (expected executable for $platform)"
    return 1
}

# Darling maps the Linux host filesystem into /Volumes/SystemRoot.
darling_path() {
    local absolute
    absolute="$(realpath -m -- "$1")" || return 1
    printf '/Volumes/SystemRoot%s' "$absolute"
}

# One implementation for all targets: compile, execute/test (where possible),
# and compare Stage 2/3. The compiler must emit the final linked executable.
bootstrap_target() {
    local platform="$1" project="$2" runtime="$3" base_dir="$4" suffix="$5"
    local -a stages=("$base_dir/hydrogen-stage1$suffix" "$base_dir/hydrogen-stage2$suffix" "$base_dir/hydrogen-stage3$suffix")
    local -a pending=("$base_dir/hydrogen-stage1.pending$suffix" "$base_dir/hydrogen-stage2.pending$suffix" "$base_dir/hydrogen-stage3.pending$suffix")
    local i stage_number current previous
    local -a command=() help_command=()

    if [[ ! -f "$project" ]]; then
        PLATFORM_STATUS["$platform"]="SKIPPED"
        PLATFORM_REASON["$platform"]="project not found: $project"
        warning "$platform: ${PLATFORM_REASON[$platform]}"
        return 0
    fi

    for ((i=0; i<3; i++)); do
        stage_number=$((i + 1))
        current="${stages[i]}"
        rm -f -- "${pending[i]}"

        # Do not attempt Stage 2/3 without an execution environment.
        if (( i > 0 )); then
            if [[ "$platform" == Windows && "$TEST_WINDOWS" != true ]]; then
                PLATFORM_STATUS["$platform"]="PARTIAL"
                PLATFORM_REASON["$platform"]="Stage 1 built; Windows execution skipped: $WINDOWS_TEST_REASON"
                return 0
            fi
            if [[ "$platform" == macOS && "$TEST_MACOS" != true ]]; then
                PLATFORM_STATUS["$platform"]="PARTIAL"
                PLATFORM_REASON["$platform"]="Stage 1 built; macOS execution skipped: $MACOS_TEST_REASON"
                return 0
            fi
        fi

        if (( i == 0 )); then
            command=("$BOOTSTRAP" build "$project" -o "${pending[i]}")
        else
            previous="${stages[i-1]}"
            case "$platform" in
                Linux) command=("$previous" build "$project" -o "${pending[i]}") ;;
                Windows) command=("$WINE" "$previous" build "$project" -o "${pending[i]}") ;;
                macOS)
                    command=("$DARLING" shell "$(darling_path "$previous")" build
                        "$(darling_path "$project")" -o "$(darling_path "${pending[i]}")") ;;
            esac
        fi

        step "Bootstrapping $platform Stage $stage_number..."
        if ! try_run 0 "${command[@]}"; then
            mark_failure "$platform" "Stage $stage_number compilation: $LAST_FAILURE"
            return 1
        fi
        if ! check_binary_type "$platform" "${pending[i]}"; then
            mark_failure "$platform" "Stage $stage_number image validation: $LAST_FAILURE"
            return 1
        fi
        if ! mv -f -- "${pending[i]}" "$current" || ! chmod +x -- "$current"; then
            mark_failure "$platform" "could not publish Stage $stage_number executable: $current"
            return 1
        fi
        PRODUCED["$platform:$stage_number"]="$current"
        PLATFORM_STATUS["$platform"]="PARTIAL"
        PLATFORM_REASON["$platform"]="Stages 1-$stage_number built; Stage 2/3 comparison not yet verified"

        # Stage 1 can still be generated without Wine or Darling installed.
        if [[ "$platform" == Windows && "$TEST_WINDOWS" != true ]]; then
            PLATFORM_REASON["$platform"]="Stage 1 built; verification unavailable: $WINDOWS_TEST_REASON"
            return 0
        fi
        if [[ "$platform" == macOS && "$TEST_MACOS" != true ]]; then
            PLATFORM_REASON["$platform"]="Stage 1 built; verification unavailable: $MACOS_TEST_REASON"
            return 0
        fi

        case "$platform" in
            Linux) help_command=("$current" --help) ;;
            Windows) help_command=("$WINE" "$current" --help) ;;
            macOS) help_command=("$DARLING" shell "$(darling_path "$current")" --help) ;;
        esac
        step "Testing $platform Stage $stage_number..."
        if ! try_run 1 "${help_command[@]}"; then
            mark_failure "$platform" "Stage $stage_number execution: $LAST_FAILURE"
            return 1
        fi
    done

    step "Verifying $platform Stage 2 and Stage 3..."
    if ! cmp -s -- "${stages[1]}" "${stages[2]}"; then
        sha256sum -- "${stages[1]}" "${stages[2]}" >> "$LOG_FILE" 2>&1 || true
        mark_failure "$platform" "Stage 2 and Stage 3 differ (see SHA-256 hashes in $LOG_FILE)"
        return 1
    fi
    sha256sum -- "${stages[1]}" "${stages[2]}" >> "$LOG_FILE" 2>&1 || true
    PLATFORM_STATUS["$platform"]="PASSED"
    PLATFORM_REASON["$platform"]="Stages 2 and 3 are byte-identical"
    draw_progress "$platform Stage 2/3 byte-identical." "${GREEN}✓${RESET}"
    return 0
}

# Check whether the prerequisites exist, but always attempt cross-compilation
# of Stage 1, even without Wine/Darling.
bootstrap_target Linux "$LINUX_PROJECT_FILE" native "$LINUX_DIR" "" || true
bootstrap_target Windows "$WINDOWS_PROJECT_FILE" wine "$WINDOWS_DIR" .exe || true
bootstrap_target macOS "$MACOS_PROJECT_FILE" darling "$MACOS_DIR" "" || true

# The UI SDK is an optional desktop dependency, not a prerequisite for a
# freestanding compiler. When Qt 6.8+ is installed, build its native host here,
# so 'hydrogen-stage1 build <ui.hyproj> -o app' works with no environment setup.
# Set HYDROGEN_BOOTSTRAP_UI=off to skip this optional step on headless systems.
if [[ -x "$LINUX_STAGE1" && "${HYDROGEN_BOOTSTRAP_UI:-auto}" != off ]]; then
    UI_BUILD_DIR="$BUILD_DIR/ui"
    if cmake -S "$PROJECT_DIR" -B "$UI_BUILD_DIR" \
        -DCMAKE_BUILD_TYPE=Release -DHYDROGEN_BUILD_UI=ON \
        >"$STEP_LOG_DIR/hyui-configure.log" 2>&1 &&
       cmake --build "$UI_BUILD_DIR" --target hyui --parallel \
        >"$STEP_LOG_DIR/hyui-build.log" 2>&1; then
        success "Native HYUI desktop tools ready in $UI_BUILD_DIR"
    else
        warning "Optional HYUI SDK not built (requires Qt 6.8+); see $STEP_LOG_DIR/hyui-configure.log and hyui-build.log"
    fi
fi


# ------------------------------------------------------------------------------
# Full report -- only count artifacts produced during this invocation.
# ------------------------------------------------------------------------------

trap - ERR
# Clear the completed progress display before showing the report.
if [[ -t 1 ]]; then
    printf '\033[2J\033[H'
else
    printf '\n'
fi
printf '╔══════════════════════════════════════════════════════╗\n'
printf '║                Hydrogen Bootstrap Report             ║\n'
printf '╚══════════════════════════════════════════════════════╝\n'
printf '\nProject: %s\n' "$PROJECT_DIR"
printf '\nStage 0:    %s\nBootstrap:  %s\n' "$STAGE0" "$BOOTSTRAP"

for platform in Linux Windows macOS; do
    printf '\n%s: %s\n' "$platform" "${PLATFORM_STATUS[$platform]}"
    for number in 1 2 3; do
        key="$platform:$number"
        if [[ -n "${PRODUCED[$key]:-}" ]]; then
            printf '  Stage %s: %s\n' "$number" "${PRODUCED[$key]}"
        else
            printf '  Stage %s: not produced this run\n' "$number"
        fi
    done
    printf '  Result: %s\n' "${PLATFORM_REASON[$platform]}"
done

printf '\nFull log: %s\n' "$LOG_FILE"
printf 'Stage logs: %s\n\n' "$STEP_LOG_DIR"

# ALL_TARGETS_REQUIRED=1 is suitable for CI. By default a partial bootstrap is
# nonfatal if at least one platform passed (e.g. macOS still under development).
if [[ "${ALL_TARGETS_REQUIRED:-0}" == 1 ]]; then
    for platform in Linux Windows macOS; do
        if [[ "${PLATFORM_STATUS[$platform]}" != PASSED ]]; then exit 1; fi
    done
    exit 0
fi
for platform in Linux Windows macOS; do
    if [[ "${PLATFORM_STATUS[$platform]}" == PASSED ]]; then exit 0; fi
done
exit 1
