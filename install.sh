#!/usr/bin/env bash
# dev-setup: Ghostty + herdr + Bash + Starship, fully self-contained.
# Every config lives in this file. Running it installs missing tools, backs up
# any existing configs to ~/.config/dev-setup-backup/<timestamp>/, then writes them.
set -euo pipefail

BACKUP=~/.config/dev-setup-backup/$(date +%Y%m%d-%H%M%S)

# write <target> : stdin -> target, backing up an existing real file first
write() {
  mkdir -p "$(dirname "$1")"
  if [ -L "$1" ]; then rm "$1"
  elif [ -e "$1" ]; then mkdir -p "$BACKUP"; cp "$1" "$BACKUP/$(echo "${1#$HOME/}" | tr / _)"; fi
  cat > "$1"
  echo "wrote $1"
}

# --- Tools -------------------------------------------------------------------
OS=$(uname -s)   # Darwin or Linux
export PATH="$HOME/.local/bin:$PATH"

has_ghostty() { command -v ghostty >/dev/null || [ -d /Applications/Ghostty.app ]; }
has_font() {
  if [ "$OS" = Darwin ]; then ls ~/Library/Fonts /Library/Fonts 2>/dev/null | grep -i 'JetBrainsMonoNerd' >/dev/null
  else fc-list 2>/dev/null | grep -i 'JetBrainsMono Nerd' >/dev/null; fi
}

missing=()
has_ghostty                   || missing+=(ghostty)
has_font                      || missing+=(jetbrains-mono-nerd-font)
command -v jq >/dev/null       || missing+=(jq)
command -v herdr >/dev/null    || missing+=(herdr)
command -v bash >/dev/null     || missing+=(bash)
command -v starship >/dev/null || missing+=(starship)
[ -f ~/.local/share/blesh/ble.sh ] || missing+=(blesh)

if [ ${#missing[@]} -eq 0 ]; then
  echo "All packages present."
else
  echo "Missing packages: ${missing[*]}"
fi

# Linux package manager for distro packages
pkg_install() {
  if   command -v apt-get >/dev/null; then sudo apt-get install -y "$@"
  elif command -v dnf     >/dev/null; then sudo dnf install -y "$@"
  elif command -v pacman  >/dev/null; then sudo pacman -S --noconfirm "$@"
  elif command -v zypper  >/dev/null; then sudo zypper install -y "$@"
  else echo "  no known package manager; install manually: $*"; return 1; fi
}

if [ "$OS" = Darwin ] && ! command -v brew >/dev/null && [ ${#missing[@]} -gt 0 ]; then
  echo "Homebrew is required on macOS: https://brew.sh"; exit 1
fi

manual=()
for p in ${missing[@]+"${missing[@]}"}; do
  echo "Installing $p..."
  case "$OS:$p" in
    Darwin:ghostty)                   brew install --cask ghostty ;;
    Darwin:jetbrains-mono-nerd-font)  brew install --cask font-jetbrains-mono-nerd-font ;;
    Darwin:jq|Darwin:bash|Darwin:starship) brew install "$p" ;;
    Linux:jq|Linux:bash)              pkg_install "$p" || manual+=("$p") ;;
    Linux:starship)                   curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b ~/.local/bin ;;
    Linux:ghostty)                    manual+=("ghostty (see https://ghostty.org/docs/install/binary)") ;;
    Linux:jetbrains-mono-nerd-font)
      mkdir -p ~/.local/share/fonts/JetBrainsMono &&
      curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz |
        tar -xJ -C ~/.local/share/fonts/JetBrainsMono && fc-cache -f >/dev/null ;;
    *:herdr)                          curl -fsSL https://herdr.dev/install.sh | sh ;;
    *:blesh)
      ble_tmp=$(mktemp -d)
      curl -fsSL https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz |
        tar -xJ -C "$ble_tmp"
      bash "$ble_tmp/ble-nightly/ble.sh" --install "$HOME/.local/share"
      rm -rf "$ble_tmp" ;;
  esac
done
if [ ${#manual[@]} -gt 0 ]; then
  echo "Install these yourself, then re-run: ${manual[*]}"
fi
HERDR_BIN=$(command -v herdr || echo ~/.local/bin/herdr)
BASH_BIN=$(command -v bash) || { echo "bash is required; install it and re-run."; exit 1; }

# --- Ghostty -----------------------------------------------------------------
write ~/.config/ghostty/config <<EOF
# Start in herdr (persistent session)
command = $HERDR_BIN

# ctrl+w is the herdr prefix: pass it through instead of closing the window
keybind = ctrl+w=unbind

# ctrl+k is handled by herdr (clear_pane)
keybind = ctrl+k=unbind

# Let Bash's line editor and Herdr's copy mode receive selection shortcuts.
keybind = shift+left=unbind
keybind = shift+right=unbind
keybind = shift+up=unbind
keybind = shift+down=unbind
keybind = ctrl+shift+left=unbind
keybind = ctrl+shift+right=unbind
keybind = ctrl+shift+up=unbind
keybind = ctrl+shift+down=unbind
EOF

# --- herdr -------------------------------------------------------------------
write ~/.config/herdr/config.toml <<EOF
onboarding = false

[terminal]
default_shell = "$BASH_BIN"
EOF
cat >> ~/.config/herdr/config.toml <<'EOF'

[keys]
prefix = "ctrl+w"
focus_pane_left = "prefix+left"
focus_pane_down = "prefix+down"
focus_pane_up = "prefix+up"
focus_pane_right = "prefix+right"
split_vertical = "prefix+shift+backslash"   # prefix+|
close_pane = ""   # replaced by the confirming command below
close_tab = ""
clear_pane = "ctrl+k"
new_tab = ""      # replaced by the directory-named command below
# Output selection: Ctrl+Shift+Space, Space, arrows; Enter copies, Esc clears/exits.
copy_mode = ["prefix+[", "ctrl+shift+space"]

# prefix+x: confirm before closing the focused pane
[[keys.command]]
key = "prefix+x"
type = "popup"
width = 40
height = 3
command = """sh -c 'id=$(herdr pane current | sed -E "s/.*\\"pane_id\\":\\"([^\\"]+)\\".*/\\1/"); printf "Close pane %s? [y/N] " "$id"; read -r a; [ "$a" = y ] && herdr pane close "$id"; sleep 0.3; $HOME/.config/herdr/tab-renumber.sh'"""

# prefix+c: new tab in the current directory (herdr.bash names it)
[[keys.command]]
key = "prefix+c"
type = "shell"
command = """sh -c 'd=$(herdr pane current | sed -E "s/.*\\"foreground_cwd\\":\\"([^\\"]+)\\".*/\\1/"); herdr tab create --cwd "$d" --focus'"""

# prefix+X: close the tab, then renumber the rest
[[keys.command]]
key = "prefix+shift+x"
type = "popup"
width = 40
height = 3
command = """sh -c 't=$(herdr pane current | jq -r .result.pane.tab_id); printf "Close tab? [y/N] "; read -r a; [ "$a" = y ] && herdr tab close "$t"; sleep 0.3; $HOME/.config/herdr/tab-renumber.sh'"""
EOF

write ~/.config/herdr/tab-renumber.sh <<'EOF'
#!/bin/sh
# Relabel every tab in the workspace as "<position>:<name>", keeping the name part.
# Usage: tab-renumber.sh [workspace_id] [tab_id new_name]
ws=${1:-$HERDR_WORKSPACE_ID}
[ -n "$ws" ] || ws=$(herdr pane current | jq -r '.result.pane.workspace_id')
herdr tab list --workspace "$ws" |
  jq -r --arg t "${2:-}" --arg n "${3:-}" '.result.tabs | to_entries[] |
    (if .value.tab_id == $t then $n else (.value.label | sub("^[0-9]+:"; "")) end) as $name |
    "\(.key + 1):\($name)" as $new | select($new != .value.label) |
    "\(.value.tab_id)\t\($new)"' |
  while IFS="$(printf '\t')" read -r id label; do
    herdr tab rename "$id" "$label" >/dev/null
  done
EOF
chmod +x ~/.config/herdr/tab-renumber.sh

write ~/.config/herdr/herdr.bash <<'EOF'
# Keep tabs named "<index>:<folder>" and renumber them at each prompt.
if [[ -n ${HERDR_TAB_ID:-} ]] && command -v jq >/dev/null; then
  _herdr_tab_name() {
    "$HOME/.config/herdr/tab-renumber.sh" "${HERDR_WORKSPACE_ID:-}" "$HERDR_TAB_ID" "${PWD##*/}" 2>/dev/null || :
  }
  # Preserve other prompt hooks and avoid registering twice when re-sourced.
  if declare -p PROMPT_COMMAND 2>/dev/null | grep -q 'declare -a'; then
    case ";${PROMPT_COMMAND[*]};" in
      *"_herdr_tab_name"*) ;;
      *) PROMPT_COMMAND+=(_herdr_tab_name) ;;
    esac
  else
    case ";${PROMPT_COMMAND:-};" in
      *"_herdr_tab_name"*) ;;
      *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_herdr_tab_name" ;;
    esac
  fi
fi
EOF

# --- Starship ----------------------------------------------------------------
write ~/.config/starship.toml <<'EOF'
"$schema" = 'https://starship.rs/config-schema.json'

format = """
$username\
$hostname\
$directory\
$git_branch\
$git_state\
$git_status\
$cmd_duration\
$line_break\
$python\
$character"""

[directory]
style = "blue"

[character]
success_symbol = "[❯](purple)"
error_symbol = "[❯](red)"
vimcmd_symbol = "[❮](green)"

[git_branch]
format = "[$branch]($style)"
style = "bright-black"

[git_status]
format = "[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)"
style = "cyan"
conflicted = "​"
untracked = "​"
modified = "​"
staged = "​"
renamed = "​"
deleted = "​"
stashed = "≡"

[git_state]
format = '\([$state( $progress_current/$progress_total)]($style)\) '
style = "bright-black"

[cmd_duration]
format = "[$duration]($style) "
style = "yellow"

[python]
format = "[$virtualenv]($style) "
style = "bright-black"
detect_extensions = []
detect_files = []
EOF

write ~/.config/herdr/selection.bash <<'EOF'
# ble.sh adds Shift selection while retaining the configured Bash prompt.
if declare -F bleopt >/dev/null; then
  bleopt complete_auto_complete= highlight_syntax= highlight_filename= highlight_variable=
  bleopt exec_elapsed_enabled=0
  ble-bind -m emacs -f 'C-S-up' '@marked backward-line'
  ble-bind -m emacs -f 'C-S-down' '@marked forward-line'
  ble-bind -m emacs -f 'C-S-left' '@marked backward-cword'
  ble-bind -m emacs -f 'C-S-right' '@marked forward-cword'
  ble-bind -m selection -f 'C-S-up' backward-line
  ble-bind -m selection -f 'C-S-down' forward-line
fi
EOF

# --- Bash and migration from the previous zsh setup ----------------------------
# Preserve user startup settings, removing only the old setup integrations.
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || continue
  rc_tmp=$(mktemp)
  sed -e '/^# Starship prompt$/d' \
      -e '/^eval "$(starship init bash)"$/d' \
      -e '/^eval "$(starship init zsh)"$/d' \
      -e '/^# herdr tab names$/d' \
      -e '/^source ~\/.config\/herdr\/herdr.zsh$/d' \
      -e '/^source ~\/dev-setup\/zsh\/herdr.zsh$/d' "$rc" > "$rc_tmp"
  if ! cmp -s "$rc" "$rc_tmp"; then write "$rc" < "$rc_tmp"; fi
  rm "$rc_tmp"
done

if ! grep -q '.config/herdr/herdr.bash' ~/.bashrc 2>/dev/null; then
  rc_tmp=$(mktemp)
  if [ -f ~/.bashrc ]; then cat ~/.bashrc > "$rc_tmp"; fi
  printf '\n# herdr tab names\nsource ~/.config/herdr/herdr.bash\n' >> "$rc_tmp"
  write ~/.bashrc < "$rc_tmp"
  rm "$rc_tmp"
fi

if ! grep -q '^# dev-setup: load Bash selection support$' ~/.bashrc; then
  rc_tmp=$(mktemp)
  cat > "$rc_tmp" <<'EOF'
# dev-setup: load Bash selection support
if [[ $- == *i* && ! ${BLE_VERSION:-} && -r ~/.local/share/blesh/ble.sh ]]; then
  source -- ~/.local/share/blesh/ble.sh --attach=none
fi

EOF
  cat ~/.bashrc >> "$rc_tmp"
  cat >> "$rc_tmp" <<'EOF'

# dev-setup: enable Bash selection support after other shell settings
source ~/.config/herdr/selection.bash
if [[ $- == *i* && ${BLE_VERSION:-} ]]; then ble-attach; fi
EOF
  write ~/.bashrc < "$rc_tmp"
  rm "$rc_tmp"
fi

# Starship integrates with ble.sh when the line editor has already loaded.
if ! grep -q 'starship init bash' ~/.bashrc; then
  rc_tmp=$(mktemp)
  cat ~/.bashrc > "$rc_tmp"
  printf '\n# Starship prompt\neval "$(starship init bash)"\n' >> "$rc_tmp"
  write ~/.bashrc < "$rc_tmp"
  rm "$rc_tmp"
fi

herdr config check
herdr server reload-config >/dev/null 2>&1 || true
echo "Done. Open a new Ghostty window."
