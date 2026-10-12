# dev-setup

Install Ghostty, Herdr, Bash, Starship, Go/GVM, and Bash text selection:

```sh
bash install.sh
```

On macOS, install [Homebrew](https://brew.sh) first. The installer uses Homebrew
Bash rather than the system Bash, installs `gawk` for ble.sh, and writes Ghostty's
native configuration under `~/Library/Application Support/com.mitchellh.ghostty/`.
Both GUI launches and Bash startup load the Homebrew environment. Herdr uses login
Bash on macOS and interactive non-login Bash on Linux; existing login settings are
preserved when adding `.bash_profile`. The account's default shell is unchanged.

Linux uses the available Bash and distro package manager. Ghostty must be installed
manually if missing; the installer prints its installation link. Generated configs
and managed Bash startup entries are backed up under
`~/.config/dev-setup-backup/<timestamp>/` before replacement.

| Action | macOS | Linux |
| --- | --- | --- |
| Herdr prefix | Cmd+W | Ctrl+W |
| New space | Prefix, W, N | Prefix, W, N |
| New Herdr tab in the current directory | Prefix, C | Prefix, C |
| Clear pane | Cmd+K | Ctrl+K |
| Select command text | Shift+Arrow | Shift+Arrow |
| Select command text by word | Option+Shift+Left/Right | Ctrl+Shift+Left/Right |
| Select to beginning/end of line | Cmd+Shift+Left/Right | Shift+Home/End |
| Enter output selection mode | Cmd+Shift+Space or Prefix, [ | Ctrl+Shift+Space or Prefix, [ |

In output selection mode, press Space to start selection, use arrows to extend it,
and Enter to copy; Esc exits. macOS keeps Ghostty's native Cmd+C/Cmd+V copy/paste.

Starship is initialized before ble.sh draws the first prompt. Go and GVM are loaded
in Bash, while the Go prompt module stays hidden. An existing working GVM default
is preserved; otherwise the latest installed stable Go is selected, or the latest
stable binary is installed. Set `DEV_SETUP_GO_VERSION=goX.Y.Z` when running the
installer to choose a specific version.

Installer integration checks run in temporary homes with mocked installers:

```sh
python3 -m unittest discover -s tests -v
```
