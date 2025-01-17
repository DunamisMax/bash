#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Script Name: example_script.sh
# Description: [Brief description of what the script does]
# Author: Your Name | License: MIT
# Version: 1.0.0
# ------------------------------------------------------------------------------
#
# Usage:
#   sudo ./example_script.sh [options]
#   Options:
#     -h, --help    Display this help message and exit
#
# ------------------------------------------------------------------------------

# Enable strict mode: exit on error, undefined variables, or command pipeline failures
set -Eeuo pipefail
trap 'log ERROR "Script failed at line $LINENO with exit code $?."' ERR

# ------------------------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------------------------
LOG_FILE="/var/log/example_script.log"
VERBOSE=2
# Define other global variables and arrays here
# Example: PACKAGES=(git curl wget)

# ------------------------------------------------------------------------------
# LOGGING FUNCTION
# ------------------------------------------------------------------------------
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Define color codes
    local RED='\033[0;31m'
    local YELLOW='\033[0;33m'
    local GREEN='\033[0;32m'
    local BLUE='\033[0;34m'
    local NC='\033[0m'  # No Color

    # Validate log level and set color
    case "${level^^}" in
        INFO)
            local color="${GREEN}"
            ;;
        WARN|WARNING)
            local color="${YELLOW}"
            level="WARN"
            ;;
        ERROR)
            local color="${RED}"
            ;;
        DEBUG)
            local color="${BLUE}"
            ;;
        *)
            local color="${NC}"
            level="INFO"
            ;;
    esac

    # Ensure the log file exists and is writable
    if [[ -z "${LOG_FILE:-}" ]]; then
        LOG_FILE="/var/log/example_script.log"
    fi
    if [[ ! -e "$LOG_FILE" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi

    # Format the log entry
    local log_entry="[$timestamp] [$level] $message"

    # Append to log file
    echo "$log_entry" >> "$LOG_FILE"

    # Output to console based on verbosity
    if [[ "$VERBOSE" -ge 2 ]]; then
        printf "${color}%s${NC}\n" "$log_entry" >&2
    elif [[ "$VERBOSE" -ge 1 && "$level" == "ERROR" ]]; then
        printf "${color}%s${NC}\n" "$log_entry" >&2
    fi
}

# ------------------------------------------------------------------------------
# HELPER FUNCTIONS
# ------------------------------------------------------------------------------
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log ERROR "This script must be run as root."
        exit 1
    fi
}

usage() {
    grep '^#' "$0" | sed 's/^#//'
    exit 0
}

# ------------------------------------------------------------------------------
# MAIN FUNCTION: Installs Enlightenment Desktop and GUI
# ------------------------------------------------------------------------------
install_gui() {
  export DEBIAN_FRONTEND=noninteractive

  # Remove LightDM if installed to avoid configuration prompts
  if dpkg -l | grep -q lightdm; then
    log INFO "Removing LightDM to avoid configuration prompts..."
    apt-get remove --purge -y lightdm
  fi

  # Step 1: Installing git and Cloning
  log INFO "Installing Git..."
  apt-get update
  apt-get install -y git

  if [ -d "efl" ]; then
    log INFO "Repository 'efl' already exists. Pulling latest changes..."
    cd efl
    git pull
    cd ..
  else
    log INFO "Cloning the EFL repository..."
    git clone https://git.enlightenment.org/enlightenment/efl.git
  fi

  # Step 2: Installing Dependencies for EFL
  log INFO "Installing build tools and dependencies for EFL..."
  apt-get install -y build-essential check meson ninja-build

  apt-get install -y \
    libssl-dev libsystemd-dev libjpeg-dev libglib2.0-dev libgstreamer1.0-dev \
    liblua5.2-dev libfreetype-dev libfontconfig-dev libfribidi-dev \
    libavahi-client-dev libharfbuzz-dev libibus-1.0-dev libx11-dev libxext-dev \
    libxrender-dev libgl1-mesa-dev libgif-dev libtiff5-dev libpoppler-dev \
    libpoppler-cpp-dev libspectre-dev libraw-dev librsvg2-dev libudev-dev \
    libmount-dev libdbus-1-dev libpulse-dev libsndfile1-dev libxcursor-dev \
    libxcomposite-dev libxinerama-dev libxrandr-dev libxtst-dev libxss-dev \
    libgstreamer-plugins-base1.0-dev doxygen libopenjp2-7-dev libscim-dev \
    libxdamage-dev libwebp-dev libunwind-dev libheif-dev libavif-dev libyuv-dev \
    libinput-dev

  log INFO "Configuring, building, and installing EFL from source..."
  cd efl
  meson -Dlua-interpreter=lua build
  ninja -C build
  ninja -C build install
  cd ..

  log INFO "Updating PKG_CONFIG_PATH in /etc/profile..."
  local profile="/etc/profile"
  local pkg_config_line='export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:/usr/local/lib/pkgconfig'
  if ! grep -Fxq "${pkg_config_line}" "${profile}"; then
    echo "${pkg_config_line}" | tee -a "${profile}" >/dev/null
  else
    log INFO "PKG_CONFIG_PATH line already present in ${profile}."
  fi

  log INFO "Refreshing library paths..."
  ldconfig

  log INFO "Installing Xorg, GDM3, and Enlightenment desktop environment..."
  apt-get install -y xorg gdm3 enlightenment

  log INFO "Enabling GDM3 for auto-start on boot..."
  systemctl enable gdm3

  log INFO "Installing backup desktop environments (XFCE, i3)..."
  apt-get install -y xfce4 i3 rofi i3lock i3blocks feh xterm alacritty ranger \
      network-manager network-manager-gnome pavucontrol alsa-utils picom \
      polybar fonts-powerline fonts-noto

  apt purge lightdm
  log INFO "Full GDM/Enlightenment/i3/XFCE installation complete."
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------
main() {
    # Parse input arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            *) 
                log WARN "Unknown option: $1"
                usage
                ;;
        esac
    done

    check_root
    log INFO "Script execution started."

    # Call your main functions in order
    install_gui

    log INFO "Script execution finished."
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi