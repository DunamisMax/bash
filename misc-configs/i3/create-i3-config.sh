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
# Function: Create i3 config file
# ------------------------------------------------------------------------------
create_i3_config() {
  log INFO "Starting creation of i3 configuration..."

  local config_dir="/home/sawyer/.config/i3"
  local config_file="/home/sawyer/.config/i3/config"

  # Create configuration directory if it doesn't exist
  if [[ ! -d "$config_dir" ]]; then
    mkdir -p "$config_dir"
    log INFO "Created directory: $config_dir"
  fi

  # Backup existing config if it exists
  if [[ -f "$config_file" ]]; then
    local backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$config_file" "$backup_file"
    log INFO "Existing i3 config backed up to $backup_file"
  fi

  # Create new i3 config file
  cat > "$config_file" <<'EOF'
# ------------------------------------------------------------------------------
#_____ ________                              _____________
#___(_)__|__  /        _____________ _______ ___  __/___(_)_______ _
#__  / ___/_ < _________  ___/_  __ \__  __ \__  /_  __  / __  __ `/
#_  /  ____/ / _/_____// /__  / /_/ /_  / / /_  __/  _  /  _  /_/ /
#/_/   /____/          \___/  \____/ /_/ /_/ /_/     /_/   _\__, /
#                                                          /____/
# ------------------------------------------------------------------------------
# High DPI, Addons Setup, and Custom Bindings
# ------------------------------------------------------------------------------

# Use Mod4 (Super/Windows key) as the modifier key
set $mod Mod4

# ------------------------------------------------------------------------------
# Appearance & DPI Scaling
# ------------------------------------------------------------------------------

# Increase default font size for high DPI displays using JetBrains Mono
font pango:"JetBrains Mono" 16

# Set default window border style and thickness
for_window [class="^.*"] border pixel 2

# Apply DPI scaling using xrandr on startup
# Replace "YOUR_MONITOR_OUTPUT" with your actual monitor identifier (e.g., eDP-1, HDMI-1)
exec_always --no-startup-id xrandr --output YOUR_MONITOR_OUTPUT --scale 1x1 --dpi 192

# ------------------------------------------------------------------------------
# Autostart Applications
# ------------------------------------------------------------------------------

# Start picom for compositing effects (transparency, shadows, etc.)
exec_always --no-startup-id picom --config ~/.config/picom/picom.conf

# Launch polybar (if configured) after i3 starts
exec_always --no-startup-id ~/.config/polybar/launch.sh

# Set desktop background using feh (adjust path to your wallpaper)
exec_always --no-startup-id feh --bg-scale /path/to/your/wallpaper.jpg

# ------------------------------------------------------------------------------
# Keybindings for Launchers and Utilities
# ------------------------------------------------------------------------------

# Launch terminal (Alacritty) with Mod+Enter
bindsym $mod+Return exec alacritty

# Launch alternative terminal (xterm) with Mod+Shift+Enter
bindsym $mod+Shift+Return exec xterm

# Launch Rofi as application launcher with Mod+d
bindsym $mod+d exec --no-startup-id rofi -show drun -modi drun,run,window -theme ~/.config/rofi/theme.rasi

# Lock screen using i3lock with Mod+Shift+l
bindsym $mod+Shift+l exec --no-startup-id i3lock -i /path/to/lockscreen/image.png

# Open Ranger file manager in Alacritty with Mod+Shift+e
bindsym $mod+Shift+e exec alacritty -e ranger

# Volume control using pavucontrol with Mod+Shift+p
bindsym $mod+Shift+p exec --no-startup-id pavucontrol

# ------------------------------------------------------------------------------
# Window Management Keybindings
# ------------------------------------------------------------------------------

# Standard window focus navigation
bindsym $mod+j focus left
bindsym $mod+k focus down
bindsym $mod+l focus up
bindsym $mod+semicolon focus right

# Standard window movement
bindsym $mod+Shift+j move left
bindsym $mod+Shift+k move down
bindsym $mod+Shift+l move up
bindsym $mod+Shift+semicolon move right

# Split orientation selection
bindsym $mod+h split h
bindsym $mod+v split v

# Reload and restart i3 configuration
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart

# Exit i3 session
bindsym $mod+Shift+e exec --no-startup-id i3-msg exit

# ------------------------------------------------------------------------------
# Workspace Management
# ------------------------------------------------------------------------------

# Define workspaces with icons for visual clarity
set $ws1 ""
set $ws2 ""
set $ws3 ""
set $ws4 ""
set $ws5 ""
set $ws6 ""
set $ws7 ""
set $ws8 ""
set $ws9 ""

# Switch to workspace shortcuts
bindsym $mod+1 workspace $ws1
bindsym $mod+2 workspace $ws2
bindsym $mod+3 workspace $ws3
bindsym $mod+4 workspace $ws4
bindsym $mod+5 workspace $ws5
bindsym $mod+6 workspace $ws6
bindsym $mod+7 workspace $ws7
bindsym $mod+8 workspace $ws8
bindsym $mod+9 workspace $ws9

# Move focused container to specified workspace
bindsym $mod+Shift+1 move container to workspace $ws1
bindsym $mod+Shift+2 move container to workspace $ws2
bindsym $mod+Shift+3 move container to workspace $ws3
bindsym $mod+Shift+4 move container to workspace $ws4
bindsym $mod+Shift+5 move container to workspace $ws5
bindsym $mod+Shift+6 move container to workspace $ws6
bindsym $mod+Shift+7 move container to workspace $ws7
bindsym $mod+Shift+8 move container to workspace $ws8
bindsym $mod+Shift+9 move container to workspace $ws9

# ------------------------------------------------------------------------------
# i3blocks for Status Bar
# ------------------------------------------------------------------------------

bar {
    status_command i3blocks
    font pango:DejaVu Sans Mono 14
    workspace_buttons yes

    # Adjust bar height for high DPI displays
    height 30

    # Colors for the bar (customize as preferred)
    colors {
        background       #282828
        statusline       #ebdbb2
        separator        #3c3836

        focused_workspace  #458588 #458588 #ffffff
        active_workspace   #3c3836 #3c3836 #ebdbb2
        inactive_workspace #282828 #282828 #a89984
        urgent_workspace   #cc241d #cc241d #ffffff
    }
}

# ------------------------------------------------------------------------------
# Floating Windows Rules
# ------------------------------------------------------------------------------

# Allow certain applications to float
for_window [class="^Pavucontrol$"] floating enable
for_window [class="^Rofi$"] floating enable
for_window [class="^feh$"] floating enable
for_window [class="^pinentry$"] floating enable

# ------------------------------------------------------------------------------
# Miscellaneous Settings
# ------------------------------------------------------------------------------

# Use gaps between windows (requires i3-gaps)
gaps inner 10
gaps outer 10

# Optionally set separate horizontal and vertical gaps
# gaps horiz 10
# gaps vert 10

# Focus follows mouse pointer
focus_follows_mouse yes

# Smart border behavior: hide borders when unnecessary
smart_borders on

# ------------------------------------------------------------------------------
# End of Configuration
# ------------------------------------------------------------------------------

# Notes:
# - Ensure the required theme files for rofi, polybar, and picom are installed and configured.
# - Adjust paths (for wallpapers, lockscreen images, configuration scripts) as needed.
# - Replace "YOUR_MONITOR_OUTPUT" in the xrandr command with your actual monitor identifier.
# - Tweak font sizes, gap values, and other settings as needed for personal preference and performance.
EOF

  log INFO "i3 configuration file created at $config_file"
}