# dev-setup

Install Ghostty, Herdr, Bash, Starship, and Go/GVM:

```sh
./install.sh
```

Run it as your desktop user, without `sudo`. It installs only missing packages,
leaves identical configuration files and the active keyboard profile alone, and
configures the MX Keys Mini on Deepin or Ubuntu/GNOME when that profile needs updating.
If it needs a system change but was launched without a terminal for sudo, it
prints a command to run from a terminal instead of failing the whole install.

On macOS, install [Homebrew](https://brew.sh) first. The installer uses Homebrew
Bash rather than the system Bash and writes Ghostty's
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
| Enter output selection mode | Cmd+Shift+Space or Prefix, [ | Ctrl+Shift+Space or Prefix, [ |

Bash uses ble.sh for interactive command-line selection, including Shift+Arrow
and the configured Command/Option selection shortcuts. Open a new shell after
installing. On macOS, Cmd+Shift+Left/Right selects from the cursor to the
beginning/end of the current line, and Cmd+Shift+Up/Down selects to the
beginning/end of the command text. Herdr output selection is separate from
editing the current command.

In output selection mode, press Space to start selection, use arrows to extend
it, and Enter to copy; Esc exits. macOS keeps Ghostty's native Cmd+C/Cmd+V
copy/paste.

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

## Keyboard setup by platform

Run `bash install.sh` as your regular user on both platforms. macOS gets its
Ghostty shortcuts from the installer. On Deepin or Ubuntu/GNOME, the installer also runs
`configure_keyboard.sh` when it detects the MX Keys Mini; that script asks for
sudo to install/reload the device profile and clean the previous system map.
Headless Linux and Linux sessions without that keyboard skip this system step.
To apply the MX Keys Mini profile manually later, run `bash configure_keyboard.sh`
from the desktop; restore it with `bash configure_keyboard.sh revert` (or `--reset`).

### Deepin 25 and Herdr

Run `bash configure_keyboard.sh` in the Deepin session. It installs keyd if needed
and creates a profile for the connected MX Keys Mini. Run
`bash configure_keyboard.sh revert` to remove that profile; existing Deepin
shortcuts are restored and other keyd profiles are left alone. The pictured MX
Keys Mini for Mac has Control, Option, Command, Space, Command, Option along
its bottom row. The profile defaults to the observed connection mode, where the physical
Command key sends Alt. Use `--cmd-key meta` if Command instead sends Meta. Use `--diagnose` to check
raw keys and `--print-config` to preview the profile.

With the US English layout, the key left of 1 types backtick (`) and Shift+key
types tilde (~). The script removes the former managed acute-key mapping.

Command acts like Ctrl for application shortcuts. Command+Shift+Left/Right
selects to the beginning/end of a line; Command+Shift+Up/Down selects to the
beginning/end of a document. Option+Shift+Left/Right selects by word.
Command+Space opens Deepin search, Command+Backspace sends Delete for selected
items, Command+Q closes the window, and Command+Tab
switches applications; Option+Tab switches windows of the current application.
Hold Shift to reverse either switcher. Command+Space opens search without
assigning search to Shift+Space. Command+3 captures the screen; Command+4 or Command+5
opens Deepin's screenshot tool using its default shortcut. These desktop
shortcuts depend on Deepin's default bindings.

In Herdr, Command+Shift+Space enters output selection mode; press Space, move
with the arrows, and press Enter to copy. The keyboard script configures Ghostty
to pass selection keys through; reload Ghostty or open a new window afterward. Command+C still sends Ctrl+C in terminals,
which interrupts the foreground process; use the terminal's Ctrl+Shift+C/V
for clipboard operations. Keyd cannot distinguish a terminal from other apps.
The Deepin setup also installs the XKB layout **MX Keys Mini For Mac - en-us** and adds it to the current Fcitx 5 input-method group alongside existing layouts. To install only the layout, run `bash configure_keyboard.sh --install-layout`. It preserves the existing default and selected input method; select the new layout from the input-method switcher. The US ANSI legends use the normal US characters, with AltGr+comma / AltGr+Shift+comma providing ç / Ç for the Option+C shortcut. The layout is registered in the user’s XKB configuration, so it works on Deepin systems with a read-only `/usr`. On X11, Fcitx uses the system’s `us(altgr-intl)` variant to apply the same printed US keys and cedilla shortcut; its other AltGr characters follow that variant. Fcitx may restart once to discover the new layout. `revert` removes the shortcut profile but leaves the installed layout available.

This profile does not change media keys.

### Mac-style MX Keys Mini on Ubuntu/GNOME

The keyboard script runs as your desktop user. It uses
[keyd](https://github.com/rvaiya/keyd), which handles input before
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
| Command+Up / Down | Beginning / end of document |
| Command+Shift+Left / Right | Select to beginning / end of line |
| Command+Shift+Up / Down | Select to beginning / end of document |
| Option+Shift+Left / Right | Select by word |
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
