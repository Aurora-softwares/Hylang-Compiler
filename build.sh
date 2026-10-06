#!/usr/bin/env bash

# ==============================================================================
# Hydrogen Compiler Bootstrap
#
# Builds the C++ Stage 0 compiler, then bootstraps the self-hosting Hydrogen
# compiler through stages 1, 2, and 3 before verifying reproducibility.
#
# Usage:
#   ./bootstrap.sh
#   ./bootstrap.sh /path/to/Hylang-Compiler
#
# ==============================================================================

set -Eeuo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

DEFAULT_PROJECT_DIR="/home/rsmith/Projects/Aurora-Softwares/Hylang-Compiler"
PROJECT_DIR="${1:-$DEFAULT_PROJECT_DIR}"

BUILD_DIR="$PROJECT_DIR/build"
SELF_HOST_DIR="$BUILD_DIR/self_hosting"

PROJECT_FILE="$PROJECT_DIR/samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj"

STAGE0="$BUILD_DIR/hy"
BOOTSTRAP="$SELF_HOST_DIR/hydrogen-bootstrap"
STAGE1="$SELF_HOST_DIR/hydrogen-stage1"
STAGE2="$SELF_HOST_DIR/hydrogen-stage2"
STAGE3="$SELF_HOST_DIR/hydrogen-stage3"

LOG_FILE="$BUILD_DIR/bootstrap.log"

TOTAL_STEPS=11
CURRENT_STEP=0

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

die() {
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

draw_progress() {
    local message="$1"
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

    printf "\r${CYAN}[%s%s]${RESET} %3d%%  %s" \
        "$bar_filled" \
        "$bar_empty" \
        "$percent" \
        "$message"

    if (( CURRENT_STEP == TOTAL_STEPS )); then
        printf "\n"
    fi
}

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    draw_progress "$1"
}

# Run a command silently, logging stdout/stderr to bootstrap.log.
run() {
    printf "\n\n==> %s\n" "$*" >> "$LOG_FILE"

    if ! "$@" >> "$LOG_FILE" 2>&1; then
        printf "\n"
        die "Command failed: $*"
    fi
}

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
        chmod +x "$file" || die "Could not make $description executable."
    fi
}

# ------------------------------------------------------------------------------
# Error handling
# ------------------------------------------------------------------------------

cleanup() {
    # Never leave incomplete compiler stages looking like successful builds.
    rm -f \
        "$STAGE1.pending" \
        "$STAGE2.pending" \
        "$STAGE3.pending" \
        2>/dev/null || true
}

on_error() {
    local exit_code=$?

    printf "\n"

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
            info "Detected Debian/Ubuntu package manager."
            info "Installing build-essential and cmake..."

            sudo apt-get update
            sudo apt-get install -y build-essential cmake
            ;;

        dnf)
            info "Detected Fedora/RHEL package manager."
            info "Installing GCC, GCC C++, make and CMake..."

            sudo dnf install -y gcc gcc-c++ make cmake
            ;;

        yum)
            info "Detected yum package manager."
            info "Installing GCC, GCC C++, make and CMake..."

            sudo yum install -y gcc gcc-c++ make cmake
            ;;

        pacman)
            info "Detected Arch Linux package manager."
            info "Installing base-devel and CMake..."

            sudo pacman -S --needed --noconfirm base-devel cmake
            ;;

        zypper)
            info "Detected openSUSE package manager."
            info "Installing compiler tools and CMake..."

            sudo zypper --non-interactive install \
                gcc \
                gcc-c++ \
                make \
                cmake
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
printf "║           Hydrogen Compiler Bootstrap               ║\n"
printf "╚══════════════════════════════════════════════════════╝\n"
printf "${RESET}\n"

printf "Project: %s\n\n" "$PROJECT_DIR"

# ------------------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------------------

if [[ ! -d "$PROJECT_DIR" ]]; then
    die "Project directory does not exist:
  $PROJECT_DIR"
fi

if [[ ! -f "$PROJECT_DIR/CMakeLists.txt" ]]; then
    die "No CMakeLists.txt was found in:
  $PROJECT_DIR

This does not appear to be the Hydrogen compiler source directory."
fi

require_file "$PROJECT_FILE" "Hydrogen self-hosting project"

mkdir -p "$BUILD_DIR"
mkdir -p "$SELF_HOST_DIR"

# Reset log each run.
: > "$LOG_FILE"

info "Checking build requirements..."
check_dependencies
success "Build requirements available."

# Remove stale pending files from previous failed builds.
cleanup

# ------------------------------------------------------------------------------
# Stage 0
# ------------------------------------------------------------------------------

step "Configuring Stage 0 build..."

run cmake \
    -S "$PROJECT_DIR" \
    -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release

step "Building C++ Stage 0 compiler..."

run cmake \
    --build "$BUILD_DIR" \
    --target hy \
    --parallel

require_executable "$STAGE0" "Stage 0 compiler"

step "Testing Stage 0 compiler..."

run "$STAGE0" --help

# ------------------------------------------------------------------------------
# Bootstrap compiler
# ------------------------------------------------------------------------------

step "Building temporary bootstrap compiler..."

rm -f "$BOOTSTRAP"

run "$STAGE0" \
    build \
    "$PROJECT_FILE" \
    -o "$BOOTSTRAP"

require_executable "$BOOTSTRAP" "bootstrap compiler"

step "Testing bootstrap compiler..."

run "$BOOTSTRAP" --help

# ------------------------------------------------------------------------------
# Stage 1
# ------------------------------------------------------------------------------

step "Bootstrapping Stage 1..."

rm -f "$STAGE1.pending"

run "$BOOTSTRAP" \
    build \
    "$PROJECT_FILE" \
    -o "$STAGE1.pending"

require_executable "$STAGE1.pending" "Stage 1 pending compiler"

mv "$STAGE1.pending" "$STAGE1"
chmod +x "$STAGE1"

step "Testing Stage 1 compiler..."

run "$STAGE1" --help

# ------------------------------------------------------------------------------
# Stage 2
# ------------------------------------------------------------------------------

step "Bootstrapping Stage 2..."

rm -f "$STAGE2.pending"

run "$STAGE1" \
    build \
    "$PROJECT_FILE" \
    -o "$STAGE2.pending"

require_executable "$STAGE2.pending" "Stage 2 pending compiler"

mv "$STAGE2.pending" "$STAGE2"
chmod +x "$STAGE2"

step "Testing Stage 2 compiler..."

run "$STAGE2" --help

# ------------------------------------------------------------------------------
# Stage 3
# ------------------------------------------------------------------------------

step "Bootstrapping Stage 3..."

rm -f "$STAGE3.pending"

run "$STAGE2" \
    build \
    "$PROJECT_FILE" \
    -o "$STAGE3.pending"

require_executable "$STAGE3.pending" "Stage 3 pending compiler"

mv "$STAGE3.pending" "$STAGE3"
chmod +x "$STAGE3"

step "Testing Stage 3 compiler..."

run "$STAGE3" --help

# ------------------------------------------------------------------------------
# Reproducibility check
# ------------------------------------------------------------------------------

step "Verifying Stage 2 and Stage 3..."

{
    printf "\n\n==> SHA-256 reproducibility check\n"
    sha256sum "$STAGE2" "$STAGE3"
} >> "$LOG_FILE" 2>&1

if cmp -s "$STAGE2" "$STAGE3"; then
    success "Stage 2 and Stage 3 are byte-identical."
else
    printf "\n"

    warning "Stage 2 and Stage 3 are NOT byte-identical."

    printf "\nSHA-256 hashes:\n"
    sha256sum "$STAGE2" "$STAGE3"

    printf "\n"
    die "The self-hosting compiler did not reach a reproducible fixed point."
fi

# ------------------------------------------------------------------------------
# Complete
# ------------------------------------------------------------------------------

# Disable ERR trap now that everything succeeded.
trap - ERR

printf "\n"

printf "${GREEN}${BOLD}"
printf "╔══════════════════════════════════════════════════════╗\n"
printf "║              Bootstrap successful!                  ║\n"
printf "╚══════════════════════════════════════════════════════╝\n"
printf "${RESET}\n"

printf "Compilers produced:\n\n"
printf "  Stage 0    %s\n" "$STAGE0"
printf "  Bootstrap  %s\n" "$BOOTSTRAP"
printf "  Stage 1    %s\n" "$STAGE1"
printf "  Stage 2    %s\n" "$STAGE2"
printf "  Stage 3    %s\n" "$STAGE3"

printf "\n"
printf "Stage 2 and Stage 3 are byte-identical.\n"
printf "Build log: %s\n" "$LOG_FILE"
printf "\n"