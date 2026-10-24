#!/usr/bin/env bash
# dev-setup: Ghostty + herdr + Bash + Starship + GVM/Go, fully self-contained.
# Every config lives in this file. Running it installs missing tools, backs up
# any existing configs to ~/.config/dev-setup-backup/<timestamp>/, then writes them.
set -euo pipefail

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo "Run ./install.sh as your desktop user, without sudo." >&2
  exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BACKUP=~/.config/dev-setup-backup/$(date +%Y%m%d-%H%M%S)

# write <target> : stdin -> target, backing up an existing real file first
write() {
  local backup_file tmp
  mkdir -p "$(dirname "$1")"
  tmp=$(mktemp)
  cat > "$tmp"
  if [ ! -L "$1" ] && [ -f "$1" ] && cmp -s "$tmp" "$1"; then
    rm "$tmp"
    echo "unchanged $1"
    return
  fi
  if [ -L "$1" ]; then rm "$1"
  elif [ -e "$1" ]; then
    mkdir -p "$BACKUP"
    backup_file="$BACKUP/$(echo "${1#$HOME/}" | tr / _)"
    # A startup file can be updated several times during one run.
    [ -e "$backup_file" ] || cp "$1" "$backup_file"
  fi
  cat "$tmp" > "$1"
  rm "$tmp"
  echo "wrote $1"
}

# --- Tools -------------------------------------------------------------------
OS=$(uname -s)   # Darwin or Linux
case "$OS" in Darwin|Linux) ;; *) echo "Unsupported OS: $OS"; exit 1 ;; esac
export PATH="$HOME/.local/bin:$PATH"

# GUI apps on macOS often start without Homebrew on PATH.
if [ "$OS" = Darwin ]; then
  if ! command -v brew >/dev/null; then
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      if [ -x "$brew_bin" ]; then eval "$(SHELL=/bin/bash "$brew_bin" shellenv)"; break; fi
    done
  fi
  if ! command -v brew >/dev/null; then
    echo "Homebrew is required on macOS: https://brew.sh"; exit 1
  fi
  eval "$(SHELL=/bin/bash brew shellenv)"
  BREW_PREFIX=$(brew --prefix)
  BASH_BIN="$BREW_PREFIX/bin/bash"
  KEY_MOD=cmd
  PREFIX_MOD=cmd
else
  BASH_BIN=$(command -v bash || true)
  KEY_MOD=ctrl
  # The MX Keys Mini keyd profile sends the physical Command key as Ctrl.
  PREFIX_MOD=ctrl
fi

has_ghostty() {
  command -v ghostty >/dev/null ||
    { [ "$OS" = Darwin ] && { [ -d /Applications/Ghostty.app ] || [ -d "$HOME/Applications/Ghostty.app" ]; }; }
}
has_font() {
  if [ "$OS" = Darwin ]; then
    local font
    for font in "$HOME"/Library/Fonts/*JetBrainsMono*Nerd* /Library/Fonts/*JetBrainsMono*Nerd*; do
      [ ! -f "$font" ] || return 0
    done
    return 1
  else fc-list 2>/dev/null | grep -i 'JetBrainsMono Nerd' >/dev/null; fi
}

missing=()
# Install Bash and git before the shell integrations that use them.
[ -n "$BASH_BIN" ] && [ -x "$BASH_BIN" ] || missing+=(bash)
command -v git >/dev/null      || missing+=(git)
has_ghostty                   || missing+=(ghostty)
has_font                      || missing+=(jetbrains-mono-nerd-font)
command -v jq >/dev/null       || missing+=(jq)
command -v herdr >/dev/null    || missing+=(herdr)
command -v starship >/dev/null || missing+=(starship)
[ -s ~/.gvm/scripts/gvm ]      || missing+=(gvm)

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

manual=()
for p in ${missing[@]+"${missing[@]}"}; do
  echo "Installing $p..."
  case "$OS:$p" in
    Darwin:ghostty)                   brew install --cask ghostty ;;
    Darwin:jetbrains-mono-nerd-font)  brew install --cask font-jetbrains-mono-nerd-font ;;
    Darwin:jq|Darwin:bash|Darwin:starship|Darwin:git|Darwin:herdr) brew install "$p" ;;
    Linux:jq|Linux:bash|Linux:git)     pkg_install "$p" || manual+=("$p") ;;
    Linux:starship)                   curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b ~/.local/bin ;;
    Linux:ghostty)                    manual+=("ghostty (see https://ghostty.org/docs/install/binary)") ;;
    Linux:jetbrains-mono-nerd-font)
      mkdir -p ~/.local/share/fonts/JetBrainsMono &&
      curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz |
        tar -xJ -C ~/.local/share/fonts/JetBrainsMono && fc-cache -f >/dev/null ;;
    *:herdr)                          curl -fsSL https://herdr.dev/install.sh | sh ;;
    *:gvm)
      curl -fsSL https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer |
        GVM_NO_UPDATE_PROFILE=1 "${BASH_BIN:-bash}" ;;
  esac
done
if [ ${#manual[@]} -gt 0 ]; then
  echo "Install these yourself, then re-run: ${manual[*]}"
fi
if [ "$OS" = Linux ]; then BASH_BIN=$(command -v bash); fi
for tool in herdr jq starship git; do
  command -v "$tool" >/dev/null || { echo "$tool is required; install it and re-run."; exit 1; }
done
[ -x "$BASH_BIN" ] || { echo "bash is required; install it and re-run."; exit 1; }
[ -s ~/.gvm/scripts/gvm ] || { echo "GVM installation failed; re-run the installer."; exit 1; }
HERDR_BIN=$(command -v herdr)

# --- Go ----------------------------------------------------------------------
# Keep a working GVM default. DEV_SETUP_GO_VERSION can explicitly select another.
GVM_DEFAULT=$("$BASH_BIN" -c '
  [ -f "$HOME/.gvm/environments/default" ] || exit 0
  source "$HOME/.gvm/environments/default"
  [ -x "${GOROOT:-}/bin/go" ] && printf "%s" "$gvm_go_name"
' || true)
GO_VERSION=${DEV_SETUP_GO_VERSION:-$GVM_DEFAULT}
if [ -z "$GO_VERSION" ]; then
  GO_VERSION=$(for candidate in "$HOME"/.gvm/gos/go[0-9]*; do
    if [ -x "$candidate/bin/go" ]; then basename "$candidate"; fi
  done | sed -nE 's/^go([0-9]+\.[0-9]+(\.[0-9]+)?)$/\1/p' |
    sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
  [ -z "$GO_VERSION" ] || GO_VERSION=go$GO_VERSION
fi
if [ -z "$GO_VERSION" ]; then
  GO_VERSION=$(curl -fsSL 'https://go.dev/dl/?mode=json' | jq -r '[.[] | select(.stable)][0].version')
fi
if [ ! -x "$HOME/.gvm/gos/$GO_VERSION/bin/go" ]; then
  "$BASH_BIN" -c 'source "$HOME/.gvm/scripts/gvm" && gvm install "$1" --binary' bash "$GO_VERSION"
fi
if [ "$GO_VERSION" != "$GVM_DEFAULT" ]; then
  if [ -f ~/.gvm/environments/default ]; then
    mkdir -p "$BACKUP"
    cp ~/.gvm/environments/default "$BACKUP/gvm-environments-default"
  fi
  "$BASH_BIN" -c 'source "$HOME/.gvm/scripts/gvm" && gvm use "$1" --default --quiet' bash "$GO_VERSION"
fi
echo "Go default: $GO_VERSION (GVM)"

# --- Platform environment -----------------------------------------------------
{
  if [ "$OS" = Darwin ]; then
    printf '_dev_setup_brew_hint=%q\n' "$(command -v brew)"
  fi
  cat <<'EOF'
# Make Homebrew tools available to both GUI launches and interactive Bash.
if [[ $(uname -s) == Darwin ]]; then
  _dev_setup_brew=$(command -v brew || true)
  if [[ -z $_dev_setup_brew && -x ${_dev_setup_brew_hint:-} ]]; then
    _dev_setup_brew=$_dev_setup_brew_hint
  fi
  if [[ -z $_dev_setup_brew ]]; then
    for _dev_setup_brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [[ ! -x $_dev_setup_brew ]] || break
    done
  fi
  if [[ -x $_dev_setup_brew ]]; then
    eval "$(SHELL=/bin/bash "$_dev_setup_brew" shellenv)"
  fi
  unset _dev_setup_brew
fi
unset _dev_setup_brew_hint
case :$PATH: in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
EOF
} | write ~/.config/herdr/platform.bash

# Use a launcher so the Herdr server inherits Homebrew PATH from GUI starts too.
{
  printf '#!/bin/bash\nsource "$HOME/.config/herdr/platform.bash"\n'
  printf 'export SHELL=%q\nexec %q "$@"\n' "$BASH_BIN" "$HERDR_BIN"
} | write ~/.config/herdr/launch.sh
chmod +x ~/.config/herdr/launch.sh

# --- Ghostty -----------------------------------------------------------------
if [ "$OS" = Darwin ]; then
  GHOSTTY_CONFIG="$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
  SHELL_MODE=login
else
  GHOSTTY_CONFIG="$HOME/.config/ghostty/config"
  [ ! -f "$HOME/.config/ghostty/config.ghostty" ] || GHOSTTY_CONFIG="$HOME/.config/ghostty/config.ghostty"
  SHELL_MODE=non_login
fi
write "$GHOSTTY_CONFIG" <<EOF
# Start in herdr (persistent session)
command = "$HOME/.config/herdr/launch.sh"

# Pass the platform's prefix and clear shortcut through to herdr.
keybind = $PREFIX_MOD+w=unbind
keybind = $KEY_MOD+k=unbind

# Send Ctrl+C as the terminal interrupt byte, even when enhanced key reporting is active.
keybind = ctrl+c=text:\\x03

# Let Herdr receive the copy-mode shortcut instead of an outer-terminal binding.
keybind = $KEY_MOD+shift+space=unbind

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
if [ "$OS" = Darwin ]; then
  cat >> "$GHOSTTY_CONFIG" <<'EOF'

# Option edits by word; pass shifted Option arrows through to the shell.
macos-option-as-alt = true
keybind = alt+shift+left=unbind
keybind = alt+shift+right=unbind
keybind = cmd+shift+left=csi:1;2H
keybind = cmd+shift+right=csi:1;2F
keybind = cmd+shift+up=csi:1;6H
keybind = cmd+shift+down=csi:1;6F
EOF
fi

# --- herdr -------------------------------------------------------------------
write ~/.config/herdr/config.toml <<EOF
onboarding = false

[terminal]
default_shell = "$BASH_BIN"
shell_mode = "$SHELL_MODE"
EOF
cat >> ~/.config/herdr/config.toml <<EOF

[keys]
prefix = "$PREFIX_MOD+w"
workspace_picker = "prefix+w"
# Navigate mode also accepts prefix bindings: prefix+w, then n creates a space.
new_workspace = ["prefix+n", "prefix+shift+n"]
next_tab = "prefix+shift+right"
focus_pane_left = "prefix+left"
focus_pane_down = "prefix+down"
focus_pane_up = "prefix+up"
focus_pane_right = "prefix+right"
split_vertical = "prefix+shift+backslash"   # prefix+|
close_pane = ""   # replaced by the confirming command below
close_tab = ""
clear_pane = "$KEY_MOD+k"
new_tab = ""      # replaced by the directory-named command below
# Output selection: $KEY_MOD+shift+space, Space, arrows; Enter copies, Esc exits.
copy_mode = ["prefix+[", "$KEY_MOD+shift+space"]
EOF
cat >> ~/.config/herdr/config.toml <<'EOF'

# prefix+x: confirm before closing the focused pane
[[keys.command]]
key = "prefix+x"
type = "popup"
width = 40
height = 3
command = 'sh "$HOME/.config/herdr/close.sh" pane'

# prefix+c: new tab in the current directory (herdr.bash names it)
[[keys.command]]
key = "prefix+c"
type = "shell"
command = '"$HOME/.config/herdr/launch.sh" tab create --cwd "${HERDR_ACTIVE_PANE_CWD:-$PWD}" --focus'

# prefix+X: close the tab, then renumber the rest
[[keys.command]]
key = "prefix+shift+x"
type = "popup"
width = 40
height = 3
command = 'sh "$HOME/.config/herdr/close.sh" tab'
EOF

write ~/.config/herdr/close.sh <<'EOF'
#!/bin/sh
# Popups have no HERDR_PANE_ID. Herdr supplies the underlying active IDs instead.
kind=${1:-}
case "$kind" in
  pane) target=${HERDR_ACTIVE_PANE_ID:-} ;;
  tab) target=${HERDR_ACTIVE_TAB_ID:-} ;;
  *) printf 'Expected pane or tab.\n' >&2; exit 2 ;;
esac
if [ -z "$target" ]; then
  printf 'Cannot determine the active %s.\n' "$kind" >&2
  exit 1
fi
workspace=${HERDR_ACTIVE_WORKSPACE_ID:-}
printf 'Close %s %s? [y/N] ' "$kind" "$target"
IFS= read -r answer || exit 0
case "$answer" in y|Y|yes|YES|Yes) ;; *) exit 0 ;; esac
"$HOME/.config/herdr/launch.sh" "$kind" close "$target" >/dev/null || exit "$?"
# The workspace may have disappeared when its last tab closed.
if [ -n "$workspace" ]; then
  "$HOME/.config/herdr/tab-renumber.sh" "$workspace" 2>/dev/null || :
fi
EOF
chmod +x ~/.config/herdr/close.sh

write ~/.config/herdr/tab-renumber.sh <<'EOF'
#!/bin/bash
# Relabel every tab in the workspace as "<position>:<name>", keeping the name part.
# Usage: tab-renumber.sh [workspace_id] [tab_id new_name]
source "$HOME/.config/herdr/platform.bash"
herdr() { "$HOME/.config/herdr/launch.sh" "$@"; }
ws=${1:-${HERDR_WORKSPACE_ID:-}}
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

[golang]
disabled = true
EOF

write ~/.config/herdr/shell.bash <<'EOF'
# Shared startup for fresh Bash panes, independent of the server's environment.
export SHELL="$BASH"
source "$HOME/.config/herdr/platform.bash"
if [[ -s "$HOME/.gvm/scripts/gvm" ]] && ! declare -F gvm >/dev/null; then
  source "$HOME/.gvm/scripts/gvm"
fi
if command -v starship >/dev/null; then
  eval "$(starship init bash)"
fi
EOF

write ~/.config/herdr/readline.inputrc <<'EOF'
# Highlight marked regions in Bash Readline.
set enable-active-region on

# Option+Shift+Left/Right: select one word at a time.
"\e[1;6D": "\C-@\eb"
"\e[1;6C": "\C-@\ef"
# macOS Ghostty reports Option+Shift with modifier 4.
"\e[1;4D": "\C-@\eb"
"\e[1;4C": "\C-@\ef"

# Command+Shift+Left/Right: select to line start/end.
"\e[1;2H": "\C-@\C-a"
"\e[1;2F": "\C-@\C-e"
# Command+Shift+Up/Down: select to buffer start/end.
"\e[1;6H": "\C-@\C-a"
"\e[1;6F": "\C-@\C-e"
EOF

# Load the managed Readline bindings without replacing the user's inputrc.
if [ -f ~/.inputrc ]; then
  if ! grep -Fqx '$include ~/.config/herdr/readline.inputrc' ~/.inputrc; then
    rc_tmp=$(mktemp)
    cat ~/.inputrc > "$rc_tmp"
    printf '\n$include ~/.config/herdr/readline.inputrc\n' >> "$rc_tmp"
    write ~/.inputrc < "$rc_tmp"
    rm "$rc_tmp"
  fi
else
  write ~/.inputrc <<'EOF'
$include ~/.config/herdr/readline.inputrc
EOF
fi

# Remove the obsolete ble.sh startup support and its generated settings file.
if [ -f ~/.config/herdr/selection.bash ]; then
  mkdir -p "$BACKUP"
  backup_file="$BACKUP/.config_herdr_selection.bash"
  [ -e "$backup_file" ] || cp ~/.config/herdr/selection.bash "$backup_file"
  rm ~/.config/herdr/selection.bash
fi

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
  printf '\n# dev-setup: herdr tab names\nsource ~/.config/herdr/herdr.bash\n' >> "$rc_tmp"
  write ~/.bashrc < "$rc_tmp"
  rm "$rc_tmp"
fi

# Rebuild only our managed Bash startup header.
rc_tmp=$(mktemp)
cat > "$rc_tmp" <<'EOF'
# dev-setup: begin Bash startup
_DEV_SETUP_BASHRC_LOADED=1
source "$HOME/.config/herdr/platform.bash"
# dev-setup: end Bash startup
EOF
sed -e '/^# dev-setup: begin Bash startup$/,/^# dev-setup: end Bash startup$/d' \
    ~/.bashrc >> "$rc_tmp"
if ! cmp -s ~/.bashrc "$rc_tmp"; then write ~/.bashrc < "$rc_tmp"; fi
rm "$rc_tmp"

# Rebuild this small managed tail so reruns also migrate the old startup order.
rc_tmp=$(mktemp)
sed -e '/^# dev-setup: enable Bash selection support after other shell settings$/d' \
    -e '/^# dev-setup: GVM and Starship$/d' \
    -e '/^# dev-setup: finish interactive shell startup$/d' \
    -e '/^source ~\/.config\/herdr\/shell.bash$/d' \
    -e '/^source ~\/.config\/herdr\/selection\.bash$/d' \
    -e '/^if \[\[ \$- == \*i\* && \${BLE_VERSION:-} \]\]; then ble-attach; fi$/d' \
    ~/.bashrc > "$rc_tmp"
cat >> "$rc_tmp" <<'EOF'
# dev-setup: finish interactive shell startup
source ~/.config/herdr/shell.bash
EOF
if ! cmp -s ~/.bashrc "$rc_tmp"; then write ~/.bashrc < "$rc_tmp"; fi
rm "$rc_tmp"

# macOS login Bash reads .bash_profile, which must also load the managed .bashrc.
if [ "$OS" = Darwin ]; then
  rc_tmp=$(mktemp)
  if [ -f ~/.bash_profile ]; then
    sed '/^# dev-setup: begin Bash login$/,/^# dev-setup: end Bash login$/d' ~/.bash_profile > "$rc_tmp"
  else
    # Creating .bash_profile otherwise hides the previously active login file.
    for login_rc in "$HOME/.bash_login" "$HOME/.profile"; do
      if [ -f "$login_rc" ]; then
        printf 'source %q\n' "$login_rc" >> "$rc_tmp"
        break
      fi
    done
  fi
  cat >> "$rc_tmp" <<'EOF'
# dev-setup: begin Bash login
if [[ $- == *i* && ! ${_DEV_SETUP_BASHRC_LOADED:-} ]]; then
  source "$HOME/.bashrc"
fi
# dev-setup: end Bash login
EOF
  if ! cmp -s ~/.bash_profile "$rc_tmp"; then write ~/.bash_profile < "$rc_tmp"; fi
  rm "$rc_tmp"
fi

herdr config check
herdr server reload-config >/dev/null 2>&1 || true
if [ "$OS" = Linux ] && [ "${DEV_SETUP_SKIP_KEYBOARD:-0}" != 1 ]; then
  if [ -r /proc/bus/input/devices ] && grep -qi 'MX Keys Mini' /proc/bus/input/devices; then
    if [[ ${XDG_CURRENT_DESKTOP:-} == *GNOME* || -n ${GNOME_DESKTOP_SESSION_ID:-} ]]; then
      if bash "$SCRIPT_DIR/configure_keyboard.sh" --check; then
        : # The profile and desktop bindings already match; avoid sudo and rewrites.
      elif [ -t 0 ] && [ -t 1 ]; then
        echo "Configuring MX Keys Mini shortcuts..."
        bash "$SCRIPT_DIR/configure_keyboard.sh"
      else
        echo "MX Keys Mini setup is needed. Run bash configure_keyboard.sh from a terminal to authorize the system profile."
      fi
    else
      echo "MX Keys Mini detected outside GNOME; run configure_keyboard.sh from GNOME to install its system keyboard profile."
    fi
  else
    echo "MX Keys Mini not detected; skipping its system keyboard profile."
  fi
fi
echo "Done. Open a new Ghostty window."
