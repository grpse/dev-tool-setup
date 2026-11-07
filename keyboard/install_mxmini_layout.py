#!/usr/bin/python3
"""Register the MX Keys Mini US layout in XKB and the current Fcitx group."""
import os
from pathlib import Path
import sys
import time
import xml.etree.ElementTree as ET

LAYOUT = 'mxmini'
IM = 'keyboard-mxmini'
BACKING_LAYOUT = 'us-altgr-intl'
NAME = 'MX Keys Mini For Mac - en-us'
MARKER = '// Managed by dev-setup MX Keys Mini layout'
SYMBOLS = Path(__file__).resolve().parent / 'keyboards/mx-keys-mini-mac-en-us/mxmini'


def user_xkb():
    return Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'xkb'


def install_user(xkb=None, system_registry=Path('/usr/share/X11/xkb/rules/evdev.xml')):
    xkb = xkb or user_xkb()
    target = xkb / 'symbols' / LAYOUT
    text = MARKER + '\n' + SYMBOLS.read_text()
    if target.exists() and not target.read_text().startswith(MARKER):
        raise RuntimeError(f'Refusing to replace an unmanaged layout: {target}')
    updates = {target: text}
    for file in (xkb / 'rules/evdev.xml',):
        if not file.exists() and not system_registry.exists():
            raise RuntimeError(f'The XKB evdev registry is missing: {system_registry}')
        original = file.read_text() if file.exists() else system_registry.read_text()
        tree = ET.fromstring(original)
        matches = [entry for entry in tree.findall('./layoutList/layout')
                   if entry.findtext('./configItem/name') == LAYOUT]
        if matches:
            if len(matches) != 1 or matches[0].findtext('./configItem/description') != NAME:
                raise RuntimeError(f'Layout name {LAYOUT} already belongs to another layout in {file}')
            if not file.exists():
                updates[file] = original
            continue
        entry = '''    <layout>
      <configItem>
        <name>mxmini</name>
        <shortDescription>en</shortDescription>
        <description>MX Keys Mini For Mac - en-us</description>
        <languageList><iso639Id>eng</iso639Id></languageList>
      </configItem>
      <variantList/>
    </layout>
'''
        if original.count('</layoutList>') != 1:
            raise RuntimeError(f'Cannot locate layout list in {file}')
        updated = original.replace('  </layoutList>', entry + '  </layoutList>', 1)
        if updated == original:
            raise RuntimeError(f'Unexpected layout registry formatting in {file}')
        ET.fromstring(updated)
        updates[file] = updated
    if xkb / 'rules/evdev.xml' not in updates and not (xkb / 'rules/evdev.xml').exists():
        raise RuntimeError('The XKB evdev registry is missing')
    previous = {p: p.read_bytes() if p.exists() else None for p in updates}
    try:
        for path, content in updates.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            temp = path.with_name(path.name + '.dev-setup-tmp')
            temp.write_text(content)
            temp.chmod(0o644)
            os.replace(temp, path)
    except Exception:
        for path, old in previous.items():
            if old is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(old)
        raise


def fcitx_add():
    try:
        from gi.repository import Gio, GLib
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        dest, path, iface = 'org.fcitx.Fcitx5', '/controller', 'org.fcitx.Fcitx.Controller1'
        def call(method, params=None):
            return bus.call_sync(dest, path, iface, method, params, None,
                                 Gio.DBusCallFlags.NONE, 5000, None).unpack()
        def available():
            return any(item[0] == IM for item in call('AvailableInputMethods')[0])
        if not available():
            if not call('CanRestart')[0]:
                raise RuntimeError('Fcitx cannot restart automatically; restart it and rerun the installer')
            call('Restart')
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                time.sleep(.25)
                try:
                    if available():
                        break
                except GLib.Error:
                    pass
            else:
                raise RuntimeError('Fcitx did not discover the new layout after restarting')
        group = call('CurrentInputMethodGroup')[0]
        default, entries = call('InputMethodGroupInfo', GLib.Variant('(s)', (group,)))
        desired = [(name, BACKING_LAYOUT if name == IM else layout) for name, layout in entries]
        if not any(entry[0] == IM for entry in desired):
            desired.append((IM, BACKING_LAYOUT))
        if desired != entries:
            call('SetInputMethodGroupInfo', GLib.Variant('(ssa(ss))', (group, default, desired)))
            call('Save')
        _, updated = call('InputMethodGroupInfo', GLib.Variant('(s)', (group,)))
        if (IM, BACKING_LAYOUT) not in updated:
            raise RuntimeError('Fcitx did not retain the new input method')
        print(f'Added {NAME} to Fcitx group {group}; existing input methods were preserved.')
    except (ImportError, GLib.Error if 'GLib' in locals() else RuntimeError) as exc:
        raise RuntimeError(f'Unable to configure Fcitx: {exc}') from exc


def layout_installed():
    symbol = user_xkb() / 'symbols' / LAYOUT
    if not symbol.is_file() or symbol.read_text() != MARKER + '\n' + SYMBOLS.read_text():
        return False
    try:
        registry = ET.parse(user_xkb() / 'rules/evdev.xml')
        if not any(item.findtext('./configItem/name') == LAYOUT and
                   item.findtext('./configItem/description') == NAME
                   for item in registry.findall('./layoutList/layout')):
            return False
        from gi.repository import Gio, GLib
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        def call(method, params=None):
            return bus.call_sync('org.fcitx.Fcitx5', '/controller', 'org.fcitx.Fcitx.Controller1',
                                 method, params, None, Gio.DBusCallFlags.NONE, 3000, None).unpack()
        group = call('CurrentInputMethodGroup')[0]
        return (IM, BACKING_LAYOUT) in call('InputMethodGroupInfo', GLib.Variant('(s)', (group,)))[1]
    except Exception:
        return False


def main():
    if sys.argv[1:] == ['--check']:
        sys.exit(0 if layout_installed() else 1)
    if sys.argv[1:]:
        sys.exit('Usage: install_mxmini_layout.py [--check]')
    if os.geteuid() == 0:
        sys.exit('Run as your desktop user, not root.')
    install_user()
    fcitx_add()


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError) as exc:
        sys.exit(str(exc))
