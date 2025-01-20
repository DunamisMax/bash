#!/usr/local/bin/bash
# ------------------------------------------------------------------------------
# FreeBSD Automated Setup Script
# ------------------------------------------------------------------------------
# Automates fresh FreeBSD system configuration:
#  • Updates repositories, installs/upgrades essential software.
#  • Backs up and customizes key configuration files for security and performance.
#  • Sets up user "sawyer" with sudo privileges and a configured Bash environment.
#  • Enables/configures services: SSH, NTP (chrony), etc.
#  • Installs optional tools: Caddy, Plex, Python, Go, Rust, Zig, etc.
#
# Usage:
#  • Run as root or via sudo.
#  • Adjust variables (USERNAME, PACKAGES, etc.) as needed.
#  • Logs actions/errors to /var/log/freebsd_setup.log with timestamps.
#
# Error Handling:
#  • Uses 'set -euo pipefail' and an ERR trap for robust failure management.
#
# Compatibility:
#  • Tested on FreeBSD 13+. Verify on other versions.
#
# Author: dunamismax | License: MIT
# ------------------------------------------------------------------------------

set -Eeuo pipefail

# Check if script is run as root
if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root (e.g., sudo $0). Exiting."
  exit 1
fi

# ------------------------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------------------------
LOG_FILE="/var/log/freebsd_setup.log"
VERBOSE=2
USERNAME="sawyer"

# ------------------------------------------------------------------------------
# MAIN SCRIPT START
# You can add FreeBSD-specific functions below (e.g., pkg updates, config overwrites) and then
# call them in your "main" block at the end.
# ------------------------------------------------------------------------------

# Performing initial pkg update
pkg update

################################################################################
# Function: logging function
################################################################################
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
        LOG_FILE="/var/log/freebsd_setup.log"
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

################################################################################
# Function: handle_error
################################################################################
handle_error() {
  log ERROR "An error occurred. Check the log for details."
}

# Trap any error and output a helpful message
trap 'log ERROR "Script failed at line $LINENO. See above for details."' ERR

# ------------------------------------------------------------------------------
# Backup Function (FreeBSD Adaptation)
# ------------------------------------------------------------------------------
backup_system() {
    pkg install -y rsync
    # Variables
    local SOURCE="/"
    local DESTINATION="/home/${USERNAME}/BACKUPS"
    local TIMESTAMP
    TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
    local BACKUP_FOLDER="$DESTINATION/backup-$TIMESTAMP"
    local RETENTION_DAYS=7
    local EXCLUDES=(
        "/proc/*" "/sys/*" "/dev/*" "/run/*" "/tmp/*" "/mnt/*" "/media/*"
        "/swapfile" "/lost+found" "/var/tmp/*" "/var/cache/*" "/var/log/*"
        "/var/lib/docker/*" "/root/.cache/*" "/home/*/.cache/*" "$DESTINATION"
    )

    local EXCLUDES_ARGS=()
    for EXCLUDE in "${EXCLUDES[@]}"; do
        EXCLUDES_ARGS+=(--exclude="$EXCLUDE")
    done

    mkdir -p "$BACKUP_FOLDER"
    log INFO "Starting system backup to $BACKUP_FOLDER"
    if rsync -aAXv "${EXCLUDES_ARGS[@]}" "$SOURCE" "$BACKUP_FOLDER"; then
        log INFO "Backup completed successfully: $BACKUP_FOLDER"
    else
        log ERROR "Error: Backup process failed."
        exit 1
    fi

    log INFO "Cleaning up old backups older than $RETENTION_DAYS days."
    if find "$DESTINATION" -type d -name "backup-*" -mtime +"$RETENTION_DAYS" -exec rm -rf {} \;; then
        log INFO "Old backups removed."
    else
        log WARN "Warning: Failed to remove some old backups."
    fi
}

################################################################################
# Function: install_pkgs
# Purpose: Installs a comprehensive set of packages for development, system
# administration, networking, and security.
################################################################################
install_pkgs() {
    log INFO "Updating pkg repositories and upgrading packages..."
    if ! pkg upgrade -y; then
        log ERROR "System upgrade failed. Exiting."
        return 1
    fi

    PACKAGES=(
    # Development tools
    gcc cmake git pkgconf openssl llvm autoconf automake libtool ninja meson gettext
    gmake valgrind doxygen ccache diffutils

    # Scripting and utilities
    bash zsh fish nano screen tmate mosh htop iftop
    tree wget curl rsync unzip zip ca_root_nss sudo less neovim mc jq pigz fzf lynx
    smartmontools neofetch screenfetch ncdu dos2unix figlet toilet ripgrep

    # Libraries for Python & C/C++ build
    libffi readline sqlite3 ncurses gdbm nss lzma libxml2

    # Networking, system admin, and hacking utilities
    nmap netcat socat tcpdump wireshark aircrack-ng john hydra openvpn ipmitool bmon whois bind-tools

    # Languages and runtimes
    python39 go ruby perl5 rust

    # Containers and virtualization
    docker vagrant qemu

    # Web hosting tools
    nginx postgresql15-server postgresql15-client

    # File and backup management
    rclone

    # System monitoring and logging
    syslog-ng grafana prometheus netdata

    # Miscellaneous tools
    lsof bsdstats
)

    log INFO "Installing pkg-based build dependencies and popular packages..."
    if ! pkg install -y "${PACKAGES[@]}"; then
        log ERROR "Failed to install one or more pkg-based dependencies. Exiting."
        return 1
    fi
    log INFO "All pkg-based build dependencies and recommended packages installed successfully."

    # Ensure Go is installed
    if ! pkg info go >/dev/null 2>&1; then
        log INFO "Installing Go..."
        if ! pkg install -y go; then
            log ERROR "Failed to install Go programming environment. Exiting."
            return 1
        fi
        log INFO "Go installed."
    else
        log INFO "Go is already installed."
    fi
}

################################################################################
# Function: configure_ssh_settings
# Purpose: Install and configure OpenSSH server on FreeBSD with security best practices
# Returns:
#   0 - Success
#   1 - Failure
################################################################################
configure_ssh_settings() {
    local sshd_config="/usr/local/etc/ssh/sshd_config"
    local sshd_service="sshd"
    local pkg_name="openssh-portable"
    local TIMEOUT=30
    local retry_count=0
    local max_retries=3

    # Ensure clean environment
    export LC_ALL=C
    
    log INFO "Starting SSH server configuration..."

    # Install OpenSSH server with retry logic
    if ! pkg info "${pkg_name}" >/dev/null 2>&1; then
        while [ ${retry_count} -lt ${max_retries} ]; do
            log INFO "Installing OpenSSH Server (attempt $((retry_count + 1))/${max_retries})..."
            if pkg install -y "${pkg_name}"; then
                break
            fi
            retry_count=$((retry_count + 1))
            [ ${retry_count} -lt ${max_retries} ] && sleep 5
        done

        if [ ${retry_count} -eq ${max_retries} ]; then
            log ERROR "Failed to install OpenSSH Server after ${max_retries} attempts."
            return 1
        fi
    else
        log INFO "OpenSSH Server is already installed."
    fi

    # Create SSH directory if it doesn't exist
    if [ ! -d "/usr/local/etc/ssh" ]; then
        if ! mkdir -p "/usr/local/etc/ssh"; then
            log ERROR "Failed to create SSH configuration directory."
            return 1
        fi
        chmod 755 "/usr/local/etc/ssh"
    fi

    # Backup existing configuration if it exists
    if [ -f "${sshd_config}" ]; then
        local backup_file="${sshd_config}.bak.$(date +%Y%m%d%H%M%S)"
        if ! cp "${sshd_config}" "${backup_file}"; then
            log ERROR "Failed to create backup of sshd_config."
            return 1
        fi
        log INFO "Created backup of sshd_config at ${backup_file}"
    fi

    # Generate new sshd_config using printf instead of heredoc
    log INFO "Generating new SSH configuration..."
    {
        printf "# SSH Server Configuration - Generated on %s\n\n" "$(date)"
        printf "# Network settings\n"
        printf "Port 22\n"
        printf "Protocol 2\n"
        printf "AddressFamily any\n"
        printf "ListenAddress 0.0.0.0\n\n"
        
        printf "# Authentication settings\n"
        printf "MaxAuthTries 3\n"
        printf "PermitRootLogin no\n"
        printf "PasswordAuthentication no\n"
        printf "ChallengeResponseAuthentication no\n"
        printf "UsePAM no\n"
        printf "PubkeyAuthentication yes\n"
        printf "AuthenticationMethods publickey\n\n"
        
        printf "# Security settings\n"
        printf "X11Forwarding no\n"
        printf "AllowTcpForwarding no\n"
        printf "PermitEmptyPasswords no\n"
        printf "MaxSessions 2\n"
        printf "LoginGraceTime 30\n\n"
        
        printf "# Connection settings\n"
        printf "ClientAliveInterval 300\n"
        printf "ClientAliveCountMax 2\n"
        printf "TCPKeepAlive yes\n\n"
        
        printf "# Logging settings\n"
        printf "LogLevel VERBOSE\n"
        printf "SyslogFacility AUTH\n"
    } > "${sshd_config}.tmp"

    # Verify the temporary config file was created
    if [ ! -f "${sshd_config}.tmp" ]; then
        log ERROR "Failed to create new SSH configuration."
        return 1
    fi

    # Set proper permissions on the config file
    if ! chmod 600 "${sshd_config}.tmp"; then
        log ERROR "Failed to set permissions on new SSH configuration."
        return 1
    fi

    # Move temporary config to final location
    if ! mv "${sshd_config}.tmp" "${sshd_config}"; then
        log ERROR "Failed to move new SSH configuration to final location."
        return 1
    fi

    # Enable sshd in rc.conf using sysrc
    log INFO "Enabling SSH service..."
    if ! sysrc "${sshd_service}_enable=YES" >/dev/null 2>&1; then
        log ERROR "Failed to enable SSH service in rc.conf."
        return 1
    fi

    # Test configuration before applying
    log INFO "Testing SSH configuration..."
    if ! /usr/sbin/sshd -t -f "${sshd_config}"; then
        log ERROR "SSH configuration test failed."
        return 1
    fi

    # Restart sshd service
    log INFO "Restarting SSH service..."
    if ! service "${sshd_service}" restart >/dev/null 2>&1; then
        log ERROR "Failed to restart SSH service."
        return 1
    fi

    # Verify service is running
    retry_count=0
    while [ ${retry_count} -lt ${TIMEOUT} ]; do
        if service "${sshd_service}" status >/dev/null 2>&1; then
            # Verify SSH is listening
            if sockstat -4l | grep -q ":22"; then
                log INFO "SSH server is running and listening on port 22."
                break
            fi
        fi
        retry_count=$((retry_count + 1))
        sleep 1
    done

    if [ ${retry_count} -eq ${TIMEOUT} ]; then
        log ERROR "SSH service failed to start properly within ${TIMEOUT} seconds."
        return 1
    fi

    log INFO "SSH server configuration completed successfully."
    return 0
}
​​​​​​​
################################################################################
# Function: install_zig
################################################################################
install_zig() {
  set -euo pipefail
  log INFO "Starting installation of Zig..."

  if command -v zig &>/dev/null; then
    log INFO "Zig is already installed. Skipping Zig installation."
    return 0
  fi

  log INFO "Installing Zig..."
  ZIG_TARBALL="/tmp/zig.tar.xz"
  ZIG_INSTALL_DIR="/usr/local/zig"
  ZIG_URL="https://ziglang.org/builds/zig-linux-x86_64-0.14.0-dev.2847+db8ed730e.tar.xz"

  log INFO "Downloading Zig from $ZIG_URL..."
  if ! curl -L "$ZIG_URL" -o "$ZIG_TARBALL"; then
    log ERROR "Failed to download Zig."
    return 1
  fi

  log INFO "Extracting Zig tarball..."
  tar xf "$ZIG_TARBALL" -C /tmp/

  # Get the extracted directory name
  ZIG_EXTRACTED_DIR=$(tar -tf "$ZIG_TARBALL" | head -1 | cut -f1 -d"/")
  ZIG_EXTRACTED_DIR="/tmp/${ZIG_EXTRACTED_DIR}"

  if [[ ! -d "$ZIG_EXTRACTED_DIR" ]]; then
    log ERROR "Extraction failed: '$ZIG_EXTRACTED_DIR' does not exist!"
    return 1
  fi

  log INFO "Installing Zig to $ZIG_INSTALL_DIR..."
  rm -rf "$ZIG_INSTALL_DIR"
  mv "$ZIG_EXTRACTED_DIR" "$ZIG_INSTALL_DIR"

  log INFO "Creating symlink for Zig binary..."
  ln -sf "$ZIG_INSTALL_DIR/zig" /usr/local/bin/zig
  chmod +x /usr/local/bin/zig

  log INFO "Cleaning up temporary files..."
  rm -f "$ZIG_TARBALL"

  log INFO "Zig installation complete."
}

################################################################################
# Function: install_vscode_cli
################################################################################
install_vscode_cli() {
  log INFO "Creating symbolic link for Node.js..."

  if [ -e "/usr/local/node" ] || [ -L "/usr/local/node" ]; then
    rm -f "/usr/local/node"
  fi

  if ln -s "$(which node)" /usr/local/node; then
    log INFO "Symbolic link created at /usr/local/node."
  else
    log ERROR "Failed to create symbolic link for Node.js."
    return 1
  fi

  log INFO "Downloading Visual Studio Code CLI..."
  if curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' --output vscode_cli.tar.gz; then
    log INFO "Downloaded vscode_cli.tar.gz successfully."
  else
    log ERROR "Failed to download vscode_cli.tar.gz."
    return 1
  fi

  log INFO "Extracting vscode_cli.tar.gz..."
  if tar -xf vscode_cli.tar.gz; then
    log INFO "Extraction completed successfully."
  else
    log ERROR "Failed to extract vscode_cli.tar.gz."
    return 1
  fi

  log INFO "Visual Studio Code CLI installation steps completed."
  log INFO "Run './code tunnel --name freebsd-server' from ~ to run the tunnel"
}

################################################################################
# Function: install_font
# Purpose: Download and install the specified font on FreeBSD.
# Globals: None
# Arguments: None
# Returns:
#   0 - Success
#   1 - Failure
################################################################################
install_font() {
  local font_url="https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/FiraCode/Regular/FiraCodeNerdFont-Regular.ttf"
  local font_dir="/usr/local/share/fonts/nerd-fonts"
  local font_file="FiraCodeNerdFont-Regular.ttf"

  log INFO "Starting font installation..."

  # Create the font directory if it doesn't exist
  if [ ! -d "$font_dir" ]; then
    log INFO "Creating font directory: $font_dir"
    if ! mkdir -p "$font_dir"; then
      log ERROR "Failed to create font directory: $font_dir"
      return 1
    fi
  fi

  # Download the font
  log INFO "Downloading font from $font_url"
  if ! fetch -o "$font_dir/$font_file" "$font_url"; then
    log ERROR "Failed to download font from $font_url"
    return 1
  fi

  # Refresh font cache
  log INFO "Refreshing font cache..."
  if ! fc-cache -fv >/dev/null 2>&1; then
    log ERROR "Failed to refresh font cache."
    return 1
  fi

  log INFO "Font installation completed successfully."
  return 0
}

################################################################################
# Function: download_repositories
################################################################################
download_repositories() {
  log INFO "Downloading GitHub repositories"

  local github_dir="/home/${USERNAME}/github"
  log INFO "Creating GitHub directory at $github_dir"
  mkdir -p "$github_dir"

  log INFO "Changing to GitHub directory"
  cd "$github_dir" || exit 1

  repos=(
    "bash" "c" "religion" "windows" "hugo" "python"
  )

  for repo in "${repos[@]}"; do
    if [ -d "$repo" ]; then
      log INFO "Removing existing directory: $repo"
      rm -rf "$repo"
    fi

    log INFO "Cloning repository: $repo"
    git clone "https://github.com/dunamismax/${repo}.git"
  done

  log INFO "Download completed"

  # Permissions and ownership adjustments might differ on FreeBSD;
  # adjust groups/users as appropriate for your FreeBSD setup.
  log INFO "Setting ownership and permissions for Hugo public directory"
  chown -R www:www "${github_dir}/hugo/dunamismax.com/public"
  chmod -R 755 "${github_dir}/hugo/dunamismax.com/public"

  log INFO "Setting ownership and permissions for Hugo directory"
  chown -R sawyer:sawyer "${github_dir}/hugo"
  chmod o+rx "/home/${USERNAME}/" "$github_dir" "${github_dir}/hugo" "${github_dir}/hugo/dunamismax.com/"

  for repo in bash c c python religion windows; do
    chown -R "${USERNAME}:${USERNAME}" "${github_dir}/${repo}"
  done

  log INFO "Update repositories and permissions completed."
  cd ~
}

# ------------------------------------------------------------------------------
# FIX DIRECTORY PERMISSIONS FUNCTION
# ------------------------------------------------------------------------------

# Configuration
GITHUB_DIR="/home/sawyer/github"
HUGO_PUBLIC_DIR="/home/sawyer/github/hugo/dunamismax.com/public"
HUGO_DIR="/home/sawyer/github/hugo"
SAWYER_HOME="/home/sawyer"
BASE_DIR="/home/sawyer/github"

# NOTE: 700 == rwx for *owner only* (no permissions for group or others)
#       600 == rw for *owner only* (no permissions for group or others)
DIR_PERMISSIONS="700"   # For .git directories
FILE_PERMISSIONS="600"  # For .git files

# ------------------------------------------------------------------------------
# FUNCTION: fix_git_permissions
# ------------------------------------------------------------------------------
fix_git_permissions() {
    local git_dir="$1"
    echo "Setting stricter permissions for $git_dir"
    # Make sure the top-level .git dir has directory permissions
    chmod "$DIR_PERMISSIONS" "$git_dir"

    # Apply to all subdirectories and files inside .git
    find "$git_dir" -type d -exec chmod "$DIR_PERMISSIONS" {} \;
    find "$git_dir" -type f -exec chmod "$FILE_PERMISSIONS" {} \;

    echo "Permissions fixed for $git_dir"
}

# ------------------------------------------------------------------------------
# MAIN FUNCTION: set_directory_permissions
# ------------------------------------------------------------------------------
set_directory_permissions() {
  # 1. Make all .sh files executable under GITHUB_DIR
  log INFO "Making all .sh files executable under $GITHUB_DIR"
  find "$GITHUB_DIR" -type f -name "*.sh" -exec chmod +x {} \;

  # 2. Set ownership for directories
  log INFO "Setting ownership for $GITHUB_DIR and $SAWYER_HOME"
  chown -R sawyer:sawyer "$GITHUB_DIR"
  chown -R sawyer:sawyer "$SAWYER_HOME"

  # 3. Set ownership and permissions for Hugo public directory
  log INFO "Setting ownership and permissions for Hugo public directory"
  chmod -R 755 "$HUGO_PUBLIC_DIR"

  # 4. Set ownership and permissions for Hugo directory and related paths
  log INFO "Setting ownership and permissions for Hugo directory"
  chown -R sawyer:sawyer "$HUGO_DIR"
  chmod o+rx "$SAWYER_HOME" "$GITHUB_DIR" "$HUGO_DIR" "/home/sawyer/github/hugo/dunamismax.com"
  chown -R www:www "$HUGO_PUBLIC_DIR"

  # 5. Ensure BASE_DIR exists
  if [[ ! -d "$BASE_DIR" ]]; then
      echo "Error: Base directory $BASE_DIR does not exist."
      exit 1
  fi

  log INFO "Starting permission fixes in $BASE_DIR..."

  # 6. Find and fix .git directory permissions
  while IFS= read -r -d '' git_dir; do
      fix_git_permissions "$git_dir"
  done < <(find "$BASE_DIR" -type d -name ".git" -print0)

  log INFO "Permission setting completed."
}

# ------------------------------------------------------------------------------
# Function: Comfigure PF Firewall
# ------------------------------------------------------------------------------
configure_pf() {
  log INFO "Configuring PF firewall..."

  PF_CONF="/etc/pf.conf"
  BACKUP_CONF="/etc/pf.conf.bak.$(date +%Y%m%d%H%M%S)"

  # Backup existing PF configuration
  if [ -f "$PF_CONF" ]; then
    cp "$PF_CONF" "$BACKUP_CONF" && \
    log INFO "Existing PF configuration backed up to $BACKUP_CONF."
  fi

  # Define PF rules; adjust the interface (e.g., em0, re0) accordingly
  INTERFACE="em0"  # Replace with your network interface
  cat <<EOF > "$PF_CONF"
# PF configuration generated by configure_pf script

# Define network interface
ext_if = "$INTERFACE"

# Default block policy
set block-policy drop
block all

# Allow loopback
pass quick on lo0 all

# Allow established connections
pass out quick inet proto { tcp udp } from any to any keep state

# SSH
pass in quick on \$ext_if proto tcp to (\$ext_if) port 22 keep state

# HTTP/HTTPS
pass in quick on \$ext_if proto tcp to (\$ext_if) port { 80 443 } keep state

# Custom application ports (adjust as needed)
pass in quick on \$ext_if proto tcp to (\$ext_if) port { 8080, 32400, 8324, 32469 } keep state
pass in quick on \$ext_if proto udp to (\$ext_if) port { 1900, 5353, 32410, 32411, 32412, 32413, 32414, 32415 } keep state

# Additional default allow for outbound traffic
pass out all keep state
EOF

  # Ensure PF kernel module is loaded
  if ! kldstat | grep -q pf; then
    log INFO "Loading PF kernel module..."
    kldload pf || { log ERROR "Failed to load PF kernel module."; return 1; }
    echo 'pf_load="YES"' >> /boot/loader.conf
    log INFO "PF kernel module will load on boot."
  fi

  # Enable PF in rc.conf
  if ! grep -q '^pf_enable="YES"' /etc/rc.conf; then
    echo 'pf_enable="YES"' >> /etc/rc.conf
    log INFO "Enabled PF in /etc/rc.conf."
  else
    log INFO "PF is already enabled in /etc/rc.conf."
  fi

  # Check for /dev/pf
  if [ ! -c /dev/pf ]; then
    log ERROR "/dev/pf missing. Ensure PF kernel module is loaded."
    return 1
  fi

  # Load PF configuration
  if pfctl -nf "$PF_CONF"; then
    pfctl -f "$PF_CONF"
    log INFO "PF configuration loaded successfully."
  else
    log ERROR "Failed to validate or load PF configuration."
    return 1
  fi

  # Enable PF if not already active
  if pfctl -s info | grep -q "Status: Enabled"; then
    log INFO "PF is already active."
  else
    if pfctl -e; then
      log INFO "PF enabled."
    else
      log ERROR "Failed to enable PF."
      return 1
    fi
  fi

  log INFO "PF firewall configuration complete."
}

setup_dotfiles() {
    # Base paths
    local user_home="/home/${USERNAME}"
    local dotfiles_dir="${user_home}/github/bash/dotfiles"
    local config_dir="${user_home}/.config"
    local local_dir="${user_home}/.local"
    
    log INFO "Setting up dotfiles..."

    # Verify source directory exists
    [[ ! -d "$dotfiles_dir" ]] && {
        log ERROR "Dotfiles directory not found: $dotfiles_dir"
        return 1
    }

    # Create necessary directories
    mkdir -p "$config_dir" "$local_dir/bin" || {
        log ERROR "Failed to create config directories"
        return 1
    }

    # Define files to copy (source:destination)
    local files=(
        "${dotfiles_dir}/.bash_profile:${user_home}/"
        "${dotfiles_dir}/.bashrc:${user_home}/"
        "${dotfiles_dir}/.profile:${user_home}/"
        "${dotfiles_dir}/Caddyfile:/usr/local/etc/"
    )

    # Define directories to copy (source:destination)
    local dirs=(
        "${dotfiles_dir}/bin:${local_dir}"
        "${dotfiles_dir}/alacritty:${config_dir}"
    )

    # Copy files
    for item in "${files[@]}"; do
        local src="${item%:*}"
        local dst="${item#*:}"
        if [[ -f "$src" ]]; then
            cp "$src" "$dst" || log WARN "Failed to copy: $src"
        else
            log WARN "Source file not found: $src"
        fi
    done

    # Copy directories
    for item in "${dirs[@]}"; do
        local src="${item%:*}"
        local dst="${item#*:}"
        if [[ -d "$src" ]]; then
            cp -r "$src" "$dst" || log WARN "Failed to copy: $src"
        else
            log WARN "Source directory not found: $src"
        fi
    done

    # Set permissions
    chown -R "${USERNAME}:${USERNAME}" "$user_home"
    chown "${USERNAME}:${USERNAME}" /usr/local/etc/Caddyfile 2>/dev/null

    log INFO "Dotfiles setup complete"
    return 0
}

# ------------------------------------------------------------------------------
# Function: finalize_configuration
# ------------------------------------------------------------------------------
finalize_configuration() {
  log INFO "Finalizing system configuration..."

  cd /home/sawyer

  # Upgrade installed packages using pkg
  log INFO "Upgrading installed packages..."
  if pkg upgrade -y; then
    log INFO "Packages upgraded."
  else
    log ERROR "Package upgrade failed."
  fi
  ##############################################################################
  # Additional System Logging Information
  ##############################################################################
  log INFO "Collecting system information..."

  # Uptime
  log INFO "System Uptime: $(uptime)"

  # Disk usage for root
  log INFO "Disk Usage (root): $(df -h / | tail -1)"

  # Memory usage (FreeBSD equivalent)
  log INFO "Memory and Swap Usage:"
  vmstat -s

  # CPU information
  CPU_MODEL=$(sysctl -n hw.model 2>/dev/null || echo "Unknown")
  log INFO "CPU Model: ${CPU_MODEL}"

  # Kernel version
  log INFO "Kernel Version: $(uname -r)"

  # Network configuration
  log INFO "Network Configuration: $(ifconfig -a)"

  # End of system information collection
  log INFO "System information logged."

  log INFO "System configuration finalized."
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------
main() {
  log INFO "--------------------------------------"
  log INFO "Starting FreeBSD Automated System Configuration Script"

  # Bash script execution order:

  # System backup temporarily disabled for testing
  # backup_system
  install_pkgs
  configure_ssh_settings
  configure_pf
  install_zig
  download_repositories
  set_directory_permissions
  install_vscode_cli
  install_font
  dotfiles_load
  finalize_configuration

  log INFO "Configuration script finished successfully."
  log INFO "Enjoy FreeBSD!!!"
  log INFO "--------------------------------------"
}

# Entrypoint
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi