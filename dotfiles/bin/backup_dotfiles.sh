#!/bin/bash

# Define source directories
SOURCE_DIRS=(
    "$HOME/.config/rofi"
    "$HOME/.config/i3"
    "$HOME/.local/bin/"
    "$HOME/.config/polybar"
    "$HOME/.config/alacritty/"
)

# Define destination directory
DESTINATION="$HOME/github/bash/dotfiles"

# Ensure the destination directory exists
mkdir -p "$DESTINATION"

# Backup the folders
for DIR in "${SOURCE_DIRS[@]}"; do
    if [ -d "$DIR" ]; then
        rsync -av --delete "$DIR/" "$DESTINATION/$(basename "$DIR")"
    else
        echo "Directory $DIR does not exist, skipping."
    fi
done

# Additional files (dotfiles) to backup
DOTFILES=(
    "$HOME/.bashrc"
    "$HOME/.profile"
    "$HOME/.bash_profile"
    "$HOME/.fehbg"
    "$HOME/.Xresources"
    "$HOME/.xprofile"
    "/etc/caddy/Caddyfile"
    "/etc/chrony/chrony.conf"
)

# Backup additional dotfiles
for FILE in "${DOTFILES[@]}"; do
    if [ -f "$FILE" ]; then
        rsync -av "$FILE" "$DESTINATION/"
    else
        echo "Dotfile $FILE does not exist, skipping."
    fi
done

echo "Backup completed at $(date)."