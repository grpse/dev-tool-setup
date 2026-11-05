#!/usr/bin/env bash
# Run as your desktop user. sudo is used only for the keyd/system files.
set -euo pipefail
exec /usr/bin/python3 - "$@" <<'PY'
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

MARKER = "# Managed by dev-setup configure_keyboard.sh"
PROFILE = Path('/etc/keyd/dev-setup-mx-keys-mini.conf')
STATE = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'dev-setup/mx-keys-mini.json'
LEGACY = {'altwin:ctrl_alt_win', 'altwin:swap_alt_win', 'ctrl:swap_lalt_lctl'}
BASIC_FKEYS = 'fkeys:basic_13-24'
KEYS = [
    ('org.gnome.desktop.wm.keybindings', 'close'),
    ('org.gnome.shell.keybindings', 'toggle-application-view'),
    ('org.gnome.shell.keybindings', 'toggle-overview'),
    ('org.gnome.shell.keybindings', 'screenshot'),
    ('org.gnome.shell.keybindings', 'show-screenshot-ui'),
    ('org.gnome.desktop.interface', 'gtk-key-theme'),
]

# The privileged helper handles only the managed profile and obsolete XKB options.
ROOT_HELPER = r'''
import pathlib, re, shutil, subprocess, sys
mode, profile_text = sys.argv[1:]
deepin = mode.startswith('deepin-')
mode = mode.removeprefix('deepin-')
profile = pathlib.Path('/etc/keyd/dev-setup-mx-keys-mini.conf')
marker = '# Managed by dev-setup configure_keyboard.sh'
legacy = {'altwin:ctrl_alt_win', 'altwin:swap_alt_win', 'ctrl:swap_lalt_lctl'}
if profile.exists() and not profile.read_text().startswith(marker):
    sys.exit('Refusing to replace a profile not managed by this script: ' + str(profile))
if profile.is_symlink():
    sys.exit('Refusing a symbolic link at ' + str(profile))
keyboard = pathlib.Path('/etc/default/keyboard')
old_keyboard = keyboard.read_text() if keyboard.exists() else None
old_profile = profile.read_text() if profile.exists() else None
keyd = shutil.which('keyd') or shutil.which('keyd.rvaiya')
if mode == 'apply' and not keyd:
    sys.exit('Cannot find keyd or keyd.rvaiya after installation.')

def clean_options(match):
    options = [o for o in match[2].split(',') if o and o not in legacy]
    return match[1] + ','.join(options) + match[3]

try:
    if old_keyboard is not None and not deepin:
        cleaned = re.sub(r'(^\s*XKBOPTIONS=["\x27])([^"\x27]*)(["\x27])', clean_options,
                         old_keyboard, flags=re.M)
        if cleaned != old_keyboard:
            backup = pathlib.Path('/etc/default/keyboard.before-dev-setup-mx-keys')
            if not backup.exists():
                shutil.copy2(keyboard, backup)
            keyboard.write_text(cleaned)
    if mode == 'apply':
        profile.parent.mkdir(parents=True, exist_ok=True)
        # Reject another explicit profile for the same device. Wildcard profiles
        # are allowed: keyd gives explicit device matches priority.
        ids = set(profile_text.split('[ids]\n', 1)[1].split('[main]', 1)[0].split())
        for other in profile.parent.glob('*.conf'):
            if other == profile:
                continue
            text = other.read_text()
            section = re.search(r'^\[ids\]\s*\n(.*?)(?=^\[|\Z)', text, re.M | re.S)
            entries = [line.split('#', 1)[0].strip().removeprefix('k:')
                       for line in section[1].splitlines()] if section else []
            if any(entry == own or entry.startswith(own + ':')
                   for entry in entries for own in ids):
                raise RuntimeError('Device already has a keyd profile: ' + str(other))
        profile.write_text(profile_text)
        profile.chmod(0o644)
        subprocess.run(['systemctl', 'enable', '--now', 'keyd'], check=True)
    else:
        profile.unlink(missing_ok=True)
    if subprocess.run(['systemctl', 'is-active', '--quiet', 'keyd']).returncode == 0:
        if not keyd:
            raise RuntimeError('Cannot reload keyd: executable not found.')
        subprocess.run([keyd, 'reload'], check=True)
except Exception:
    if old_profile is None:
        profile.unlink(missing_ok=True)
    else:
        profile.write_text(old_profile)
    if old_keyboard is not None:
        keyboard.write_text(old_keyboard)
    if keyd:
        try:
            subprocess.run([keyd, 'reload'], check=False)
        except OSError:
            pass
    raise
'''


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def keyd_command():
    return shutil.which('keyd') or shutil.which('keyd.rvaiya')


def devices():
    found = []
    for block in Path('/proc/bus/input/devices').read_text().split('\n\n'):
        name = re.search(r'^N: Name="([^"]+)"', block, re.M)
        ident = re.search(r'^I: .*Vendor=([0-9a-f]+) Product=([0-9a-f]+)', block, re.M)
        if name and ident and 'mx keys mini' in name[1].lower() and 'Handlers=' in block:
            found.append(f'{ident[1]}:{ident[2]}')
    return sorted(set(found))


def config(ids, cmd_key, deepin=False):
    if cmd_key == 'alt':
        main = ('leftalt = layer(mac_command)\nrightalt = layer(mac_command)\n'
                'leftmeta = layer(mac_option)\nrightcontrol = layer(mac_option)')
    else:
        main = ('leftmeta = layer(mac_command)\nrightmeta = layer(mac_command)\n'
                'leftalt = layer(mac_option)\nrightalt = layer(mac_option)')
    profile = f'''{MARKER}
# Command input mode: {cmd_key}. Only the listed MX Keys Mini is remapped.
[ids]
{chr(10).join(ids)}

[main]
{main}

# All unspecified Command combinations behave as Control combinations.
# Physical Left Ctrl retains its normal function, including terminal interrupts.
[mac_command:C]
space = f13
q = f14
# Print opens GNOME's screenshot UI; S selects area mode (crosshair drag).
3 = S-print
4 = macro(print 250ms s)
5 = print
left = home
right = end
up = C-home
down = C-end
tab = swapm(mac_app_switch, A-tab)

[mac_app_switch:A]
tab = A-tab

# Option+Tab cycles windows of the current app; Shift reverses direction.
# Option also navigates/deletes by word. Other combinations remain Alt.
[mac_option:A]
# US International: AltGr+comma is ç; AltGr+Shift+comma is Ç.
c = G-comma
tab = A-f6
left = C-left
right = C-right
backspace = C-backspace
delete = C-delete

# Consume Shift explicitly so Mac-style shifted screenshot chords also work.
[mac_command+shift]
left = S-home
right = S-end
up = S-C-home
down = S-C-end
3 = S-print
4 = macro(print 250ms s)
5 = print

[mac_option+shift]
c = G-S-comma
'''
    if deepin:
        profile = profile.replace('space = f13', 'space = C-M-space').replace('q = f14', 'q = A-f4')
        profile = profile.replace('tab = A-f6', 'tab = swapm(mac_group_switch, A-grave)')
        profile += '''\n[mac_group_switch:A]\ntab = A-grave\n\n[mac_group_switch+shift]\ntab = S-A-grave\n\n[mac_app_switch+shift]\ntab = S-A-tab\n'''
        profile = profile.replace('[mac_command+shift]\n', '[mac_command+shift]\nspace = C-S-space\ntab = swapm(mac_app_switch, S-A-tab)\n')
        profile = profile.replace('[mac_option+shift]\n', '[mac_option+shift]\ntab = swapm(mac_group_switch, S-A-grave)\n')
        profile = profile.replace('3 = S-print', '3 = print').replace('4 = macro(print 250ms s)', '4 = C-A-a').replace('5 = print', '5 = C-A-a')
    return profile


def desktop():
    try:
        import gi
        gi.require_version('Gio', '2.0')
        from gi.repository import Gio, GLib
    except ImportError:
        sys.exit('Install python3-gi first: sudo apt install python3-gi')
    source = Gio.SettingsSchemaSource.get_default()
    for schema in {s for s, _ in KEYS} | {'org.gnome.desktop.input-sources'}:
        if source is None or source.lookup(schema, True) is None:
            sys.exit('Run this script from your GNOME desktop session: missing ' + schema)
    return Gio, GLib


def clean_desktop(Gio, basic_fkeys):
    settings = Gio.Settings.new('org.gnome.desktop.input-sources')
    original = list(settings.get_strv('xkb-options'))
    options = original
    options = [o for o in options if o not in LEGACY and o != BASIC_FKEYS]
    if basic_fkeys:
        options.append(BASIC_FKEYS)
    settings.set_strv('xkb-options', options)
    return options != original


def refresh_keymap(Gio, GLib):
    # GNOME 50.1's keyboardManager.reapply passes a layout object where an ID
    # is expected, so xkb-options changes can remain saved but unapplied.
    # Rebuilding the input-source list takes the working apply-by-ID path.
    settings = Gio.Settings.new('org.gnome.desktop.input-sources')
    original = settings.get_value('sources')
    sources = original.unpack()
    if not sources:
        return
    temporary = next((('xkb', layout) for layout in ('us', 'gb', 'de')
                      if ('xkb', layout) not in sources), None)
    if temporary is None:
        print('Log out and back in to refresh the compositor keyboard map.')
        return
    try:
        settings.set_value('sources', GLib.Variant('a(ss)', sources + [temporary]))
        Gio.Settings.sync()
        time.sleep(0.4)
    finally:
        settings.set_value('sources', original)
        Gio.Settings.sync()
    time.sleep(0.4)


def snapshot(Gio):
    saved = []
    stale = {
        'close': [['<Control>q'], ['<Super>q'], ['<Alt>q']],
        'toggle-application-view': [['<Control>space'], ['<Super>space'], ['<Alt>space']],
        'gtk-key-theme': ['Mac'],
    }
    for schema, key in KEYS:
        settings = Gio.Settings.new(schema)
        value = settings.get_user_value(key)
        data = value.unpack() if value is not None else None
        if data in stale.get(key, []):
            data = None
        saved.append({'schema': schema, 'key': key, 'value': data,
                      'type': settings.get_value(key).get_type_string()})
    return {'settings': saved, 'basic_fkeys_was_present': BASIC_FKEYS in
            Gio.Settings.new('org.gnome.desktop.input-sources').get_strv('xkb-options')}


def upgrade_state(Gio, state):
    fresh = snapshot(Gio)
    if state is None:
        return fresh
    upgraded = dict(state, settings=list(state['settings']))
    saved_keys = {(entry['schema'], entry['key']) for entry in upgraded['settings']}
    upgraded['settings'].extend(entry for entry in fresh['settings']
                               if (entry['schema'], entry['key']) not in saved_keys)
    upgraded.setdefault('basic_fkeys_was_present', fresh['basic_fkeys_was_present'])
    return upgraded


def restore_desktop(Gio, GLib, state, refresh=True):
    if state:
        for entry in state['settings']:
            settings = Gio.Settings.new(entry['schema'])
            if entry['value'] is None:
                settings.reset(entry['key'])
            else:
                settings.set_value(entry['key'], GLib.Variant(entry['type'], entry['value']))
    else:
        # Also undo the previous script when no new-format snapshot exists.
        for schema, key in KEYS:
            settings = Gio.Settings.new(schema)
            if key == 'toggle-overview':
                settings.set_strv(key, [v for v in settings.get_strv(key) if v != 'F13'])
            elif key == 'close':
                settings.reset(key)
            elif key == 'toggle-application-view':
                settings.reset(key)
            elif key == 'gtk-key-theme' and settings.get_string(key) == 'Mac':
                settings.reset(key)
    changed = clean_desktop(Gio, state.get('basic_fkeys_was_present', False) if state else False)
    Gio.Settings.sync()
    if changed and refresh:
        refresh_keymap(Gio, GLib)


def apply_desktop(Gio, GLib, state):
    # Start from the saved baseline, so repeated runs don't overwrite the backup.
    restore_desktop(Gio, GLib, state, refresh=False)
    # Ubuntu's default inet symbols translate KEY_F13 to XF86Tools (Settings),
    # and KEY_F14 to XF86Launch5. Keep our synthetic keys as F13/F14 instead.
    clean_desktop(Gio, True)
    shell = Gio.Settings.new('org.gnome.shell.keybindings')
    # F13 was assigned to the window overview by the previous version.
    shell.set_strv('toggle-overview', [v for v in shell.get_strv('toggle-overview') if v != 'F13'])
    for schema, key, binding in [
        ('org.gnome.shell.keybindings', 'toggle-application-view', 'F13'),
        ('org.gnome.desktop.wm.keybindings', 'close', 'F14'),
        ('org.gnome.shell.keybindings', 'screenshot', '<Shift>Print'),
        ('org.gnome.shell.keybindings', 'show-screenshot-ui', 'Print'),
    ]:
        settings = Gio.Settings.new(schema)
        values = list(settings.get_strv(key))
        if binding not in values:
            values.append(binding)
        settings.set_strv(key, values)
    Gio.Settings.new('org.gnome.desktop.interface').set_string('gtk-key-theme', 'Default')
    Gio.Settings.sync()
    refresh_keymap(Gio, GLib)


def already_configured(Gio, expected_profile):
    if not PROFILE.is_file() or PROFILE.read_text() != expected_profile:
        return False
    if not keyd_command() or subprocess.run(
            ['systemctl', 'is-active', '--quiet', 'keyd']).returncode != 0:
        return False

    expected = {
        ('org.gnome.shell.keybindings', 'toggle-application-view'): 'F13',
        ('org.gnome.desktop.wm.keybindings', 'close'): 'F14',
        ('org.gnome.shell.keybindings', 'screenshot'): '<Shift>Print',
        ('org.gnome.shell.keybindings', 'show-screenshot-ui'): 'Print',
    }
    for (schema, key), binding in expected.items():
        if binding not in Gio.Settings.new(schema).get_strv(key):
            return False
    if 'F13' in Gio.Settings.new('org.gnome.shell.keybindings').get_strv('toggle-overview'):
        return False
    if Gio.Settings.new('org.gnome.desktop.interface').get_string('gtk-key-theme') != 'Default':
        return False
    options = Gio.Settings.new('org.gnome.desktop.input-sources').get_strv('xkb-options')
    if BASIC_FKEYS not in options or LEGACY.intersection(options):
        return False
    keyboard = Path('/etc/default/keyboard')
    if keyboard.exists() and any(option in keyboard.read_text() for option in LEGACY):
        return False
    return True


GHOSTTY_BEGIN = '# BEGIN dev-setup keyboard selection'
GHOSTTY_END = '# END dev-setup keyboard selection'


def ghostty_selection(apply):
    root = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'ghostty'
    candidates = [root / 'config.ghostty', root / 'config']
    path = next((p for p in candidates if p.exists()), root / 'config')
    if not apply and not path.exists():
        return
    original = path.read_text() if path.exists() else ''
    pattern = re.compile(r'(?m)^' + re.escape(GHOSTTY_BEGIN) + r'\n.*?^' + re.escape(GHOSTTY_END) + r'\n?', re.S)
    cleaned = pattern.sub('', original)
    block = GHOSTTY_BEGIN + '\n' + ''.join(
        'keybind = ' + key + '=unbind\n' for key in (
            'shift+left', 'shift+right', 'shift+up', 'shift+down',
            'shift+home', 'shift+end', 'ctrl+shift+left', 'ctrl+shift+right',
            'ctrl+shift+up', 'ctrl+shift+down', 'ctrl+shift+home',
            'ctrl+shift+end', 'ctrl+shift+space')) + GHOSTTY_END + '\n'
    updated = cleaned + ('\n' if cleaned and not cleaned.endswith('\n') else '') + block if apply else cleaned
    if updated != original:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(updated)


ACUTE_BEGIN = '# Managed by dev-setup keyboard acute key'
ACUTE_STATE = STATE.parent / 'acute-x11.json'
ACUTE_DESKTOP = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'autostart/dev-setup-keyboard-acute.desktop'
ACUTE_SCRIPT = STATE.parent / 'keyboard-acute-x11.sh'


def remove_legacy_acute():
    # Restore only our previous F24 assignment, and do not overwrite later edits.
    if ACUTE_STATE.exists():
        if not os.environ.get('DISPLAY') or not shutil.which('xmodmap'):
            sys.exit('Run from the X11 desktop with xmodmap to restore the old acute-key mapping.')
        current = run(['xmodmap', '-pke'], capture_output=True, text=True).stdout
        line = next((line for line in current.splitlines() if re.match(r'^keycode\s+202\s*=', line)), '')
        if 'acute' in line:
            run(['xmodmap', '-e', json.loads(ACUTE_STATE.read_text())['previous']])
        ACUTE_STATE.unlink()
    if ACUTE_DESKTOP.exists() and ACUTE_DESKTOP.read_text().startswith(ACUTE_BEGIN):
        ACUTE_DESKTOP.unlink()
    if ACUTE_SCRIPT.exists() and 'keycode 202 = acute acute acute' in ACUTE_SCRIPT.read_text():
        ACUTE_SCRIPT.unlink()


DEEPIN_STATE = STATE.parent / 'deepin-search.json'
DEEPIN_SEARCH = 'com.deepin.dde.keybinding.system'
SEARCH_SHORTCUT = '<Control><Super>space'


def deepin_search_matches():
    try:
        from gi.repository import Gio
        values = Gio.Settings.new(DEEPIN_SEARCH).get_strv('global-search')
    except (ImportError, ValueError):
        return False
    return (DEEPIN_STATE.exists() and SEARCH_SHORTCUT in values and
            not any(value.lower() == '<shift>space' for value in values))


def deepin_search(apply):
    try:
        from gi.repository import Gio, GLib
    except ImportError:
        sys.exit('Install python3-gi to configure Deepin shortcuts.')
    settings = Gio.Settings.new(DEEPIN_SEARCH)
    if apply:
        if not DEEPIN_STATE.exists():
            value = settings.get_user_value('global-search')
            DEEPIN_STATE.parent.mkdir(parents=True, exist_ok=True)
            DEEPIN_STATE.write_text(json.dumps({'value': value.unpack() if value is not None else None}))
        values = [value for value in settings.get_strv('global-search')
                  if value.lower() != '<shift>space']
        if SEARCH_SHORTCUT not in values:
            values.append(SEARCH_SHORTCUT)
        if not settings.set_strv('global-search', values):
            raise RuntimeError('Unable to update the Deepin search shortcut.')
    elif DEEPIN_STATE.exists():
        saved = json.loads(DEEPIN_STATE.read_text())['value']
        if saved is None:
            settings.reset('global-search')
        elif not settings.set_strv('global-search', saved):
            raise RuntimeError('Unable to restore the Deepin search shortcut.')
        DEEPIN_STATE.unlink()
    Gio.Settings.sync()


KWIN_CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'kwinrc'
KWIN_STATE = STATE.parent / 'deepin-kwin-switcher.json'


def kwin_switcher(apply):
    if not apply and not KWIN_STATE.exists():
        return
    content = KWIN_CONFIG.read_text() if KWIN_CONFIG.exists() else ''
    group = re.search(r'(?m)^\[TabBox\]\s*\n(?:(?!\[).*(?:\n|$))*', content)
    section = group.group() if group else ''
    entry = re.search(r'(?m)^ApplicationsMode\s*=.*(?:\n|$)', section)
    if apply:
        if not KWIN_STATE.exists():
            KWIN_STATE.parent.mkdir(parents=True, exist_ok=True)
            KWIN_STATE.write_text(json.dumps({'previous': entry.group().rstrip('\n') if entry else None}))
        replacement = 'ApplicationsMode=1\n'
    else:
        previous = json.loads(KWIN_STATE.read_text())['previous']
        replacement = previous + '\n' if previous is not None else ''
    if entry:
        section = section[:entry.start()] + replacement + section[entry.end():]
    elif apply:
        section = section + replacement if group else '[TabBox]\n' + replacement
    if group:
        content = content[:group.start()] + section + content[group.end():]
    elif apply:
        content += ('' if not content or content.endswith('\n') else '\n') + '\n' + section
    KWIN_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    KWIN_CONFIG.write_text(content)
    run(['gdbus', 'call', '--session', '--dest', 'org.kde.KWin', '--object-path', '/KWin',
         '--method', 'org.kde.KWin.reconfigure'], stdout=subprocess.DEVNULL)
    if not apply:
        KWIN_STATE.unlink()


def main():
    parser = argparse.ArgumentParser(prog='configure_keyboard.sh', description='Mac-style MX Keys Mini shortcuts through keyd on Ubuntu/GNOME.')
    parser.add_argument('action', nargs='?', choices=['revert'], help='restore the previous keyboard configuration')
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--reset', '-r', action='store_true', help='remove this keyd profile and restore desktop shortcuts')
    group.add_argument('--status', action='store_true', help='show configuration and service state without changing anything')
    group.add_argument('--check', action='store_true', help='check whether the profile and GNOME shortcuts already match')
    group.add_argument('--diagnose', action='store_true', help='show raw modifier events for 30 seconds (sudo required)')
    group.add_argument('--print-config', action='store_true', help='print the proposed keyd profile without applying it')
    parser.add_argument('--cmd-key', choices=['alt', 'meta'], default=None,
                        help='raw key sent by physical Command: alt (default for this keyboard connection) or meta')
    args = parser.parse_args()
    args.reset = args.reset or args.action == 'revert'
    deepin = 'DDE' in os.environ.get('XDG_CURRENT_DESKTOP', '').upper() or 'deepin' in os.environ.get('XDG_CURRENT_DESKTOP', '').lower()
    args.cmd_key = args.cmd_key or 'alt'
    ids = devices()
    if args.print_config:
        if not ids:
            sys.exit('Connect the MX Keys Mini first.')
        print(config(ids, args.cmd_key, deepin), end='')
        return
    if args.status:
        print('Connected MX Keys Mini IDs:', ', '.join(ids) or 'none')
        print('Profile:', PROFILE if PROFILE.exists() else 'not installed')
        if PROFILE.exists():
            print(PROFILE.read_text())
        subprocess.run(['systemctl', 'is-active', 'keyd'], check=False)
        if deepin:
            print('Desktop: Deepin (DDE)')
            return
        Gio, _ = desktop()
        print('GNOME XKB options:', Gio.Settings.new('org.gnome.desktop.input-sources').get_strv('xkb-options'))
        print('System keyboard defaults:\n' + Path('/etc/default/keyboard').read_text())
        subprocess.run(['journalctl', '-u', 'keyd', '-n', '12', '--no-pager'], check=False)
        return
    if args.check:
        if not ids:
            print('MX Keys Mini not detected.')
            return 1
        if deepin:
            if (PROFILE.is_file() and PROFILE.read_text() == config(ids, args.cmd_key, True)
                    and keyd_command() and deepin_search_matches() and KWIN_STATE.exists()
                    and 'ApplicationsMode=1' in KWIN_CONFIG.read_text() and not ACUTE_STATE.exists()
                    and subprocess.run(['systemctl', 'is-active', '--quiet', 'keyd']).returncode == 0):
                print('MX Keys Mini profile is already configured.')
                return 0
            print('MX Keys Mini profile needs configuration.')
            return 1
        Gio, _ = desktop()
        if already_configured(Gio, config(ids, args.cmd_key, deepin)):
            print('MX Keys Mini profile is already configured.')
            return 0
        print('MX Keys Mini profile needs configuration.')
        return 1
    if args.diagnose:
        print('Press ONLY left Command, right Command, Option, and Ctrl; note the MX Keys Mini event names.', flush=True)
        print('The monitor exits after 30 seconds. No log file is saved.', flush=True)
        keyd = keyd_command()
        if not keyd:
            sys.exit('Install keyd before running diagnostics: sudo apt-get install keyd')
        result = subprocess.run(['sudo', 'timeout', '30', keyd, 'monitor'])
        if result.returncode not in (0, 124, 130):
            sys.exit(result.returncode)
        return
    if os.geteuid() == 0:
        sys.exit('Run as your desktop user: bash configure_keyboard.sh (it requests sudo when needed).')
    if deepin:
        if not args.reset and not ids:
            sys.exit('Connect the MX Keys Mini first so its device ID can be detected.')
        if not args.reset and not keyd_command():
            run(['sudo', '-v'])
            run(['sudo', 'apt-get', 'install', '-y', 'keyd'])
        profile = config(ids, args.cmd_key, True)
        started = int(time.time())
        run(['sudo', '/usr/bin/python3', '-c', ROOT_HELPER,
             'deepin-reset' if args.reset else 'deepin-apply', '' if args.reset else profile])
        recent = subprocess.run(['journalctl', '-u', 'keyd', '--since', '@' + str(started),
                                 '--no-pager', '-o', 'cat'], capture_output=True, text=True)
        if recent.returncode == 0 and re.search(r'(?im)^.*(?:error:|failed to parse|invalid config)', recent.stdout):
            sys.exit('Keyd reported an error; run bash configure_keyboard.sh --status to inspect its log.\n' + recent.stdout)
        remove_legacy_acute()
        deepin_search(not args.reset)
        kwin_switcher(not args.reset)
        ghostty_selection(not args.reset)
        print('Removed the MX Keys Mini profile.' if args.reset else
              'Installed the Deepin MX Keys Mini profile for ' + ', '.join(ids) + '.')
        if not args.reset:
            print('Command acts as Ctrl; Command+Shift+arrows selects text. Command+Space searches, Command+Q closes the window.')
            print('Herdr: Command+Shift+Space enters output selection; then Space, arrows and Enter.')
            print('Reload Ghostty configuration or open a new window to apply selection bindings.')
            print('Undo: bash configure_keyboard.sh revert')
        return
    Gio, GLib = desktop()
    if not args.reset and not ids:
        sys.exit('Connect the MX Keys Mini first so its device ID can be detected.')
    state = json.loads(STATE.read_text()) if STATE.exists() else None
    profile = config(ids, args.cmd_key, deepin)
    if not args.reset and already_configured(Gio, profile):
        print('MX Keys Mini profile and GNOME shortcuts are already configured; nothing to change.')
        return
    # Authentication happens before any changes to the desktop or system files.
    run(['sudo', '-v'])
    if not args.reset and not keyd_command():
        run(['sudo', 'apt-get', 'install', '-y', 'keyd'])
    if args.reset:
        run(['sudo', '/usr/bin/python3', '-c', ROOT_HELPER, 'reset', ''])
        restore_desktop(Gio, GLib, state)
        STATE.unlink(missing_ok=True)
        print('Removed this keyboard profile and restored desktop shortcuts. Unrelated XKB options are preserved.')
        print('Obsolete modifier mappings from the previous scripts stay removed.')
        return
    upgraded = upgrade_state(Gio, state)
    save_state = upgraded != state
    state = upgraded
    if save_state:
        STATE.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode='w', dir=STATE.parent, delete=False) as saved:
            json.dump(state, saved)
            temporary = saved.name
        os.replace(temporary, STATE)
    started = int(time.time())
    run(['sudo', '/usr/bin/python3', '-c', ROOT_HELPER, 'apply', profile])
    apply_desktop(Gio, GLib, state)
    if PROFILE.read_text() != profile:
        sys.exit('The installed profile does not match the requested configuration.')
    run(['systemctl', 'is-active', '--quiet', 'keyd'])
    recent = subprocess.run(['journalctl', '-u', 'keyd', '--since', '@' + str(started),
                             '--no-pager', '-o', 'cat'], capture_output=True, text=True)
    if recent.returncode == 0 and re.search(r'(?im)^.*(?:error:|failed to parse|invalid config)', recent.stdout):
        sys.exit('Keyd reported an error; run bash configure_keyboard.sh --status to inspect its log.\n' + recent.stdout)
    print('Installed the MX Keys Mini profile for ' + ', '.join(ids) + '.')
    print('Command: Control shortcuts; Command+Space: Show Applications (type to search); Command+Q: close focused window.')
    print('Command+Left/Right: line start/end; Option+Left/Right: word navigation; Command+Tab: switch apps.')
    print('Option+Tab: next window of the current app; Option+Shift+Tab: previous window.')
    print('Option+C / Option+Shift+C: ç / Ç with US International layout.')
    print('Command+3: full-screen screenshot; Command+4: select an area with the crosshair; Command+5: screenshot/recording controls.')
    print('Physical Left Ctrl remains Ctrl. In terminals, Command+C sends Ctrl+C; use Command+Shift+C/V for clipboard shortcuts where supported.')
    print('After migrating from the old scripts, log out and back in once to clear the old compositor keymap.')
    print('Confirm the physical keys. If Command sends meta instead of alt, rerun with --cmd-key meta.')
    print('Undo: bash configure_keyboard.sh --reset')
    subprocess.run(['journalctl', '-u', 'keyd', '-n', '8', '--no-pager'], check=False)


try:
    sys.exit(main() or 0)
except subprocess.CalledProcessError as error:
    sys.exit(f'Command failed with exit status {error.returncode}: {error.cmd[0]}')
except (OSError, ValueError) as error:
    sys.exit(str(error))
PY
