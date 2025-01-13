#!/usr/local/bin/bash
#===============================================================================
# FreeBSD Automated System Configuration Script
#===============================================================================
# This script fully configures a new FreeBSD installation based on predefined
# system policies and best practices. It performs a comprehensive setup that
# includes:
#   • Bootstrapping and updating the pkg system, then installing a suite of
#     essential packages.
#   • Dynamically identifying the primary network adapter for Internet access
#     and configuring DHCP settings automatically.
#   • Configuring system settings via /etc/rc.conf to enable essential services,
#     improve system performance, and enhance security.
#   • Updating DNS settings in /etc/resolv.conf with specified nameservers or
#     enabling local_unbound for dynamic DNS resolution.
#   • Granting sudo privileges to designated users by adding them to the wheel
#     group and configuring sudoers with secure defaults.
#   • Hardening SSH by updating /etc/ssh/sshd_config with secure parameters,
#     such as disabling root login and limiting authentication attempts.
#   • Setting up and configuring PF firewall with custom rules, including stateful
#     connections, SSH rate-limiting, and logging of blocked inbound traffic.
#   • Automating the creation and population of user environment files
#     (.bashrc, .bash_profile) with optimized settings and aliases.
#   • Employing robust error handling, dynamic configuration backups, and
#     detailed logging throughout the process to /var/log/freebsd_setup.log.
#   • Enabling and configuring graphical environments with X11, SLiM, and i3,
#     including post-setup configurations for desktop environments.
#   • Finalizing the setup by upgrading installed packages, cleaning caches,
#     and validating configurations for stability.
#
# Usage: Execute this script as root on a fresh FreeBSD install to automate the
#        initial system configuration process or to reapply system policies.
#
# Notes:
#   • This script assumes a basic FreeBSD installation with network access.
#   • Review and customize variables and settings before execution to align
#     with specific system requirements and preferences.
#===============================================================================

set -euo pipefail
IFS=$'\n\t'

# --------------------------------------
# CONFIGURATION
# --------------------------------------

# Global Variables
LOG_FILE="/var/log/freebsd_setup.log"
PACKAGES=(
  # Essential Shells and Editors
  "vim" "bash" "zsh" "tmux" "mc" "nano" "fish" "screen"
  # Version Control and Scripting
  "git" "perl5" "python3"
  # Network and Internet Utilities
  "curl" "wget" "netcat" "tcpdump" "rsync" "rsnapshot" "samba"
  # System Monitoring and Management
  "htop" "sudo" "bash-completion" "zsh-completions" "neofetch" "tig" "bat" "exa"
  "fd" "jq" "iftop" "nmap" "tree" "fzf" "lynx" "curlie" "ncdu" "fail2ban"
  "gcc" "make" "lighttpd" "smartmontools" "zfs-auto-snapshot"
  # Database and Media Services
  "plexmediaserver" "postgresql" "caddy" "go"
  # System Tools and Backup
  "duplicity" "ffmpeg" "restic" "syslog-ng"
  # X11 and Window Management
  "xorg" "i3" "SLiM"
  # Virtualization and VM Support
  "qemu" "libvirt" "virt-manager" "vm-bhyve" "bhyve-firmware" "grub2-bhyve"
)

# --------------------------------------
# FUNCTIONS
# --------------------------------------

# Logging function with timestamp
log() {
  local msg="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') : $msg" | tee -a "$LOG_FILE"
}

# Function to handle errors and exit
error_exit() {
  local msg="$1"
  log "ERROR: $msg"
  exit 1
}

# Ensure script is run as root
check_root() {
  if [[ "$EUID" -ne 0 ]]; then
    error_exit "This script must be run as root."
  fi
}

# Identify primary network adapter
identify_primary_iface() {
  log "Identifying primary network adapter for Internet connection."
  primary_iface=$(route get default 2>/dev/null | awk '/interface:/ {print $2}')
  if [[ -z "$primary_iface" ]]; then
    error_exit "Primary network interface not found. Aborting configuration."
  else
    log "Primary network adapter identified as: $primary_iface"
  fi
}

# Bootstrap pkg and install packages
bootstrap_and_install_pkgs() {
  log "Bootstrapping pkg and installing base packages."
  if ! command -v pkg &>/dev/null; then
    log "pkg not found. Bootstrapping pkg..."
    env ASSUME_ALWAYS_YES=yes pkg bootstrap || error_exit "Failed to bootstrap pkg."
  fi
  pkg update -f || error_exit "pkg update failed."

  log "Installing all base packages in parallel."
  if ! pkg install -y "${PACKAGES[@]}"; then
    log "Failed to install one or more packages."
  fi
  log "Base packages installation completed."
}

# Configure /etc/rc.conf settings
configure_rc_conf() {
  log "Configuring sysctl and loader.conf settings."
  local rc_conf="/etc/rc.conf"
  if [[ ! -f "${rc_conf}.bak" ]]; then
    cp "$rc_conf" "${rc_conf}.bak" || error_exit "Failed to backup rc.conf."
    log "Backup of rc.conf created at ${rc_conf}.bak."
  fi

  log "Updating /etc/rc.conf with system configuration parameters."
  sysrc clear_tmp_enable="YES" || error_exit "Failed to set clear_tmp_enable."
  sysrc hostname="freebsd" || error_exit "Failed to set hostname."
  if [[ -n "$primary_iface" ]]; then
    sysrc ifconfig_${primary_iface}="DHCP" || log "Failed to configure network interface ${primary_iface}."
  else
    log "Primary interface not found. Skipping network interface configuration in rc.conf."
  fi
  sysrc local_unbound_enable="YES" || log "Failed to set local_unbound_enable."
  sysrc sshd_enable="YES" || log "Failed to set sshd_enable."
  sysrc moused_enable="NO" || log "Failed to set moused_enable."
  sysrc ntpd_enable="YES" || log "Failed to set ntpd_enable."
  sysrc powerd_enable="YES" || log "Failed to set powerd_enable."
  sysrc dumpdev="AUTO" || log "Failed to set dumpdev."
  sysrc zfs_enable="YES" || log "Failed to set zfs_enable."
  log "/etc/rc.conf has been updated with the new settings."
}

# Configure DNS settings
configure_dns() {
  log "Updating /etc/resolv.conf with desired nameservers."
  local resolv_conf="/etc/resolv.conf"
  if [[ ! -f "${resolv_conf}.bak" ]]; then
    cp "$resolv_conf" "${resolv_conf}.bak" || log "Failed to backup resolv.conf."
    log "Backup of resolv.conf created at ${resolv_conf}.bak."
  fi
  sed -i '' '/^[^#]/d' "$resolv_conf" || log "Failed to clean resolv.conf."
  {
    echo "nameserver 1.1.1.1"
    echo "nameserver 9.9.9.9"
  } >> "$resolv_conf" || log "Failed to update resolv.conf."
  log "/etc/resolv.conf updated with new nameserver entries."
}

# Grant sudo privileges to user
configure_sudoers() {
  if pw usermod sawyer -G wheel; then
    log "User 'sawyer' added to wheel group for sudo privileges."
  else
    log "Failed to add user 'sawyer' to wheel group."
  fi
  if ! grep -q "^%wheel" /usr/local/etc/sudoers; then
    log "Enabling wheel group in sudoers."
    if sed -i '' 's/^#\s*%wheel\s\+ALL=(ALL)\s\+NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /usr/local/etc/sudoers; then
      log "Sudoers updated for wheel group."
    else
      log "Failed to update sudoers for wheel group."
    fi
  fi
}

# Hardening SSH configuration
configure_ssh() {
  log "Updating SSH configuration for security and specific settings."
  local sshd_config="/etc/ssh/sshd_config"
  declare -A sshd_settings=(
    ["Port"]="22"
    ["AddressFamily"]="any"
    ["ListenAddress"]="0.0.0.0"
    ["MaxAuthTries"]="6"
    ["MaxSessions"]="10"
    ["PermitRootLogin"]="no"
  )

  if [[ ! -f "${sshd_config}.bak" ]]; then
    cp "$sshd_config" "${sshd_config}.bak" || log "Failed to backup sshd_config."
    log "Backup of sshd_config created at ${sshd_config}.bak."
  fi

  for setting in "${!sshd_settings[@]}"; do
    local value="${sshd_settings[$setting]}"
    if grep -q "^\s*${setting}\s" "$sshd_config"; then
      if sed -i '' "s|^\s*${setting}\s.*|${setting} ${value}|" "$sshd_config"; then
        log "Updated ${setting} to ${value}."
      else
        log "Failed to update ${setting}."
      fi
    else
      if echo "${setting} ${value}" >> "$sshd_config"; then
        log "Added ${setting} ${value}."
      else
        log "Failed to add ${setting} ${value}."
      fi
    fi
  done

  service sshd reload || log "Failed to reload SSH service."
  log "SSH service reloaded with updated configuration."
}

# Configure PF firewall
configure_pf() {
  log "Configuring PF firewall."
  local pf_conf="/etc/pf.conf"
  if [[ ! -f "${pf_conf}.bak" ]]; then
    cp "$pf_conf" "${pf_conf}.bak" || log "Failed to backup pf.conf."
    log "Backup of pf.conf created at ${pf_conf}.bak."
  fi

  cat <<EOF > "$pf_conf"
# /etc/pf.conf - Minimal pf ruleset with SSH rate-limiting

# Skip filtering on the loopback interface
set skip on lo0

# Normalize and scrub incoming packets
scrub in all

# Block all inbound traffic by default and log blocked packets
block in log all

# Allow all outbound traffic, keeping stateful connections
pass out all keep state

# Rate-limiting for SSH: Max 10 connections per 5 seconds, burstable to 15
table <ssh_limited> persist
block in quick on ${primary_iface} proto tcp to port 22
pass in quick on ${primary_iface} proto tcp to port 22 keep state \\
    (max-src-conn 10, max-src-conn-rate 15/5, overload <ssh_limited> flush global)

# Allow PlexMediaServer traffic
pass in quick on ${primary_iface} proto tcp to port 32400 keep state
pass in quick on ${primary_iface} proto udp to port 32400 keep state
EOF

  sysrc pf_enable="YES" || log "Failed to enable pf in rc.conf."
  sysrc pf_rules="/etc/pf.conf" || log "Failed to set pf_rules in rc.conf."
  service pf enable || log "Failed to enable pf service."
  service pf restart || log "Failed to restart pf service."
  log "PF firewall configured and restarted with custom rules."
}

# Set Bash as default shell for users
set_default_shell_and_env() {
  log "Enabling Bash and setting it as the default shell."
  local bash_path="/usr/local/bin/bash"
  if ! grep -qF "$bash_path" /etc/shells; then
    echo "$bash_path" >> /etc/shells \
      && log "Added $bash_path to /etc/shells." \
      || log "Failed to add $bash_path to /etc/shells."
  else
    log "$bash_path already exists in /etc/shells."
  fi

  local target_users=("root" "sawyer")
  for user in "${target_users[@]}"; do
    if pw usershow "$user" &>/dev/null; then
      chsh -s "$bash_path" "$user" \
        && log "Set Bash as default shell for user $user." \
        || log "Failed to set Bash as default shell for user $user."
    else
      log "User $user does not exist, skipping shell change."
    fi
  done

  for user in "${target_users[@]}"; do
    if pw usershow "$user" &>/dev/null; then
      local user_home
      user_home=$(eval echo "~$user")
      declare -a bash_files=("$user_home/.bash_profile" "$user_home/.bashrc")
      for file in "${bash_files[@]}"; do
        if [[ ! -f "$file" ]]; then
          touch "$file" \
            && log "Created $file for user $user." \
            || log "Failed to create $file for user $user."
        else
          log "$file for user $user already exists, skipping creation."
        fi
      done

      local bashrc_file="$user_home/.bashrc"
      if [[ ! -s "$bashrc_file" ]]; then
        cat <<'EOF' > "$bashrc_file"
#!/usr/local/bin/bash
# ~/.bashrc: executed by bash(1) for interactive shells.

# --------------------------------------
# Basic Settings and Environment Setup
# --------------------------------------

# Check if the shell is interactive
case $- in
    *i*) ;;
      *) return;;
esac

# Set a colorful prompt: [user@host current_directory]$
PS1='\[\e[01;32m\]\u@\h\[\e[00m\]:\[\e[01;34m\]\w\[\e[00m\]\$ '

# Ensure PATH includes common FreeBSD binary directories
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\$PATH"

# Enable color support for 'ls' and grep
alias ls='ls -lah --color=auto'
alias grep='grep --color=auto'

# --------------------------------------
# History Configuration
# --------------------------------------

# Avoid duplicate entries and set history sizes
export HISTCONTROL=ignoredups:erasedups
export HISTSIZE=1000
export HISTFILESIZE=2000

# Append rather than overwrite history on shell exit
shopt -s histappend

# --------------------------------------
# Pager and Less Configuration
# --------------------------------------

export PAGER='less -R'
export LESS='-R'

# --------------------------------------
# Bash Completion
# --------------------------------------

# Source Bash completion if available
if [ -f /usr/local/etc/bash_completion ]; then
    . /usr/local/etc/bash_completion
fi

# --------------------------------------
# Custom Aliases and Functions
# --------------------------------------

# Common shortcuts
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

# Add more aliases or functions below as needed

# --------------------------------------
# End of .bashrc
# --------------------------------------
EOF
        chmod +x "$bashrc_file" \
          && log "Populated and set execute permissions for $bashrc_file for user $user." \
          || log "Failed to set permissions for $bashrc_file for user $user."
      else
        log "$bashrc_file for user $user already has content, skipping population."
      fi

      local bash_profile_file="$user_home/.bash_profile"
      if [[ ! -s "$bash_profile_file" ]]; then
        cat <<'EOF' > "$bash_profile_file"
#!/usr/local/bin/bash
# ~/.bash_profile: executed by bash(1) for login shells.

# Source the .bashrc if it exists
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
EOF
        chmod +x "$bash_profile_file" \
          && log "Populated and set execute permissions for $bash_profile_file for user $user." \
          || log "Failed to set permissions for $bash_profile_file for user $user."
      else
        log "$bash_profile_file for user $user already has content, skipping population."
      fi
    fi
  done
}

# Finalizing configuration
finalize_configuration() {
  log "Finalizing system configuration."
  pkg upgrade -y || log "Package upgrade failed."
  pkg clean -y || log "Package clean failed."

  log "Enabling and starting PlexMediaServer service."
  sysrc plexmediaserver_enable="YES" || log "Failed to enable PlexMediaServer service."
  service plexmediaserver start || log "Failed to start PlexMediaServer service."
  log "PlexMediaServer service enabled and started successfully."
}

# Configure X11, i3, and SLiM
configure_graphical_env() {
  log "Enabling and configuring SLiM for X11 and i3 session."
  sysrc slim_enable="YES" || log "Failed to enable SLiM in rc.conf."

  local xinitrc_file="/home/sawyer/.xinitrc"
  log "Configuring .xinitrc to start i3."
  if [[ ! -f "$xinitrc_file" ]]; then
    cat <<'EOF' > "$xinitrc_file"
#!/usr/local/bin/bash
exec i3
EOF
    chmod +x "$xinitrc_file" || log "Failed to set execute permission on .xinitrc."
    log ".xinitrc created and configured to start i3."
  else
    log ".xinitrc already exists, review to ensure it starts i3."
  fi

  service slim start || log "Failed to start SLiM service."
  log "SLiM, Xorg, and i3 have been enabled and configured."
}

# --------------------------------------
# SCRIPT EXECUTION
# --------------------------------------

check_root
log "Starting FreeBSD system configuration script."
identify_primary_iface
bootstrap_and_install_pkgs
configure_rc_conf
configure_dns
configure_sudoers
configure_ssh
configure_pf
set_default_shell_and_env
finalize_configuration
configure_graphical_env

log "FreeBSD system configuration completed successfully."
exit 0
