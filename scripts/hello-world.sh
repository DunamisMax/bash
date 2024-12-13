#!/usr/bin/env bash
#
# A "Hello World" script with some flair:
# - Dynamically picks a greeting based on a user-specified language (if provided)
#   or falls back to a random greeting if none is given.
# - Uses color output, arrays, associative arrays, parameter expansion tricks.
# - Handles interrupts gracefully with a trap.
# - Tries to use external tools (figlet) if available for style.
# - Demonstrates Bash best practices: `set -euo pipefail`, arrays, and functions.

set -euo pipefail
IFS=$'\n\t'

# Trap interrupt signals and clean up.
trap 'on_exit' INT TERM EXIT

on_exit() {
  # Only print a message if the script is interrupted before normal completion.
  # $RUN_COMPLETE will be set after printing the greeting.
  if [ "${RUN_COMPLETE:-0}" -eq 0 ]; then
    echo -e "\n\e[33mCaught an interrupt signal! Goodbye.\e[0m"
  fi
}

# An associative array mapping language codes to "Hello World" translations.
declare -A GREETINGS=(
  ["en"]="Hello World"
  ["fr"]="Bonjour le monde"
  ["es"]="Hola Mundo"
  ["de"]="Hallo Welt"
  ["ja"]="こんにちは世界"
  ["zh"]="你好，世界"
  ["ar"]="مرحبا بالعالم"
  ["pt"]="Olá Mundo"
  ["it"]="Ciao Mondo"
)

# Create an indexed array of keys for random selection.
LANG_KEYS=("${!GREETINGS[@]}")

# The user can specify a language code as the first argument, e.g., ./hello.sh ja
LANG_CODE="${1:-}"

# Check if LANG_CODE is known; if not provided or not recognized, pick a random one.
if [[ -z "$LANG_CODE" || -z "${GREETINGS[$LANG_CODE]+_}" ]]; then
  # Pick a random language
  LANG_CODE="${LANG_KEYS[RANDOM % ${#LANG_KEYS[@]}]}"
fi

MESSAGE="${GREETINGS[$LANG_CODE]}"

# Function to print colorful messages
print_colored() {
  local fgcolors=(31 32 33 34 35 36) # red, green, yellow, blue, magenta, cyan
  local color="${fgcolors[RANDOM % ${#fgcolors[@]}]}"
  echo -e "\e[${color}m${1}\e[0m"
}

# Attempt to pretty-print the greeting using figlet if available
print_stylish() {
  if command -v figlet >/dev/null 2>&1; then
    # Random font if multiple are installed, else default
    local fonts=("/usr/share/figlet"/*".flf" 2>/dev/null || true)
    if [ ${#fonts[@]} -gt 1 ]; then
      local random_font="${fonts[RANDOM % ${#fonts[@]}]}"
      figlet -f "$random_font" "$MESSAGE"
    else
      figlet "$MESSAGE"
    fi
  else
    print_colored "$MESSAGE"
  fi
}

# Introduce complexity: Print a header line with date and user info, and system stats.
HOST="$(hostname)"
DATE="$(date '+%Y-%m-%d %H:%M:%S')"
USERINFO="$(whoami)"
UPTIME_INFO="$(uptime -p | sed 's/up //')"

echo "----------------------------------------"
echo " Script Run Details:"
echo "   Host:    $HOST"
echo "   User:    $USERINFO"
echo "   Date:    $DATE"
echo "   Uptime:  $UPTIME_INFO"
echo "----------------------------------------"
echo

print_stylish
RUN_COMPLETE=1

# Wait a moment to let the user admire the output
sleep 1

echo
echo "Language chosen: $LANG_CODE"
echo "Done!"
