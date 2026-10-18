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
| Herdr prefix | Cmd+W | Ctrl+W (physical Cmd+W with the MX Keys Mini profile) |
| New space | Prefix, W, N | Prefix, W, N |
| New Herdr tab in the current directory | Prefix, C | Prefix, C |
| Close pane (confirm with Y, Enter) | Prefix, X | Prefix, X |
| Close whole tab (confirm with Y, Enter) | Prefix, Shift+X | Prefix, Shift+X |
| Clear pane | Cmd+K | Ctrl+K |
| Select command text | Shift+Arrow | Shift+Arrow |
| Select command text by word | Option+Shift+Left/Right | Ctrl+Shift+Left/Right |
| Select to beginning/end of line | Cmd+Shift+Left/Right | Shift+Home/End |
| Enter output selection mode | Cmd+Shift+Space or Prefix, [ | Ctrl+Shift+Space or Prefix, [ |

In output selection mode, press Space to start selection, use arrows to extend it,
and Enter to copy; Esc exits. macOS keeps Ghostty's native Cmd+C/Cmd+V copy/paste.

Starship is initialized before ble.sh draws the first prompt. Extra ble.sh exit
status labels are disabled; command errors and Starship's error indicator remain.
Close popups use Herdr's active pane/tab IDs and the managed launcher, so they work
even when the popup's PATH does not contain Herdr.

Go and GVM are loaded
in Bash, while the Go prompt module stays hidden. An existing working GVM default
is preserved; otherwise the latest installed stable Go is selected, or the latest
stable binary is installed. Set `DEV_SETUP_GO_VERSION=goX.Y.Z` when running the
installer to choose a specific version.

Installer integration checks run in temporary homes with mocked installers:

```sh
python3 -m unittest discover -s tests -v
```

## Mac-style MX Keys Mini on Ubuntu/GNOME

Run the single setup script **as your regular desktop user**. It asks for sudo
only to install/reload the keyboard profile and clean the previous system map:

```sh
bash configure_keyboard.sh
```

This uses [keyd](https://github.com/rvaiya/keyd), which handles input before
Wayland/X11 applications receive it. The profile matches the connected **MX Keys
Mini device ID**, and keeps the physical Left Ctrl key as Ctrl. It removes the
conflicting mappings left by the earlier scripts from both GNOME and
`/etc/default/keyboard`; unrelated XKB options remain configured.
It also enables `fkeys:basic_13-24`: Ubuntu otherwise translates the profile's
F13 launcher key into `XF86Tools`, which opens Settings. Reset restores whether
this function-key option was configured before setup.
The script refreshes GNOME's input sources to apply the option immediately,
then restores the original source list.

| Physical shortcut | Result |
| --- | --- |
| Command+C / V / X / A / Z | Standard Ctrl copy / paste / cut / select all / undo |
| Command+Space | Show Applications grid; type to search apps |
| Command+Q | Close the focused window |
| Command+Left / Right | Beginning / end of line |
| Command+Shift+Left / Right | Select to beginning / end of line |
| Command+Up / Down | Beginning / end of document |
| Command+Tab | Switch applications |
| Option+Tab / Option+Shift+Tab | Next / previous window of the current application |
| Option+Left / Right | Move by word |
| Option+Backspace / Delete | Delete by word |
| Option+C / Option+Shift+C | ç / Ç (US International layout) |
| Command+3 | Capture the entire screen |
| Command+4 | Open the screenshot overlay in area-selection mode; drag with the crosshair |
| Command+5 | Open GNOME's screenshot/recording controls |

Command+4 opens the [native GNOME screenshot overlay](https://help.gnome.org/gnome-help/screen-shot-record.html)
and selects area mode for you, so the crosshair is ready to drag. After selecting
the region, click the capture button. Command+5 opens the same overlay for
screenshot and recording controls. Command+Shift+3/4/5 also work.
Cmd+4 uses GNOME's Print overlay and its `S` area-selection shortcut; Cmd+3
uses Shift+Print for a full-screen capture. Existing screenshot shortcuts are
preserved, and `--reset` restores their original settings.
Option+C uses the current US International layout's AltGr+comma character;
Option+Shift+C uses its uppercase form. No custom Compose file is required.

Both Command keys are handled. Other Command combinations fall through as Ctrl
combinations. Applications decide what Ctrl does: in terminals Command+C still
interrupts, and Command+Shift+C/V provides copy/paste where supported. Closing a
window is not a guaranteed quit of every window belonging to an application.
This profile does not change letter layout, media keys, or Fn behavior.

The default profile follows your report that physical Command currently sends
**Alt** (PC/Linux firmware mode). Keep that mode while using this profile.
[Logitech documents Fn+P for PC layout and Fn+O for Mac layout](https://support.logi.com/hc/en-001/articles/360023203254-Special-Key-Combination-on-Multi-device-Multi-OS-keyboards).
If using firmware Mac mode where Command sends **Meta/Super**, install the
corresponding profile with `bash configure_keyboard.sh --cmd-key meta`.

After migrating from the previous scripts, **log out and back in once** so the
compositor also drops the old system modifier map. Inspect configuration with
`bash configure_keyboard.sh --status`. To identify the raw physical modifiers,
run `bash configure_keyboard.sh --diagnose` and press only Command, Option, and
Ctrl. The monitor exits after 30 seconds and saves no log file. Check the events
labelled MX Keys Mini, rather than the virtual keyboard's translated events.

Undo with:

```sh
bash configure_keyboard.sh --reset
```

Reset removes only this managed keyd profile and restores the saved GNOME
shortcuts (known settings from the earlier scripts return to defaults). Obsolete
modifier mappings from those earlier scripts stay removed. The original system
keyboard file is retained at `/etc/default/keyboard.before-dev-setup-mx-keys` if
it needed cleanup. Keyd itself and other profiles remain installed. If a bad
profile blocks typing, keyd documents **Backspace+Escape+Enter** as its emergency
stop sequence.

The layer design follows [keyd's Mac configuration example](https://github.com/rvaiya/keyd/blob/master/examples/macos.conf).
