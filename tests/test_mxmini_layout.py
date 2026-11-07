"""Validate the new XKB layout and registration without modifying the host."""
import importlib.util
import re
from pathlib import Path
import subprocess
import sys
import types
from unittest.mock import patch
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('mxmini_installer', ROOT / 'keyboard/install_mxmini_layout.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class LayoutTests(unittest.TestCase):
    def test_user_registration_is_idempotent_and_preserves_other_layouts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rules = root / 'usr/share/X11/xkb/rules'
            rules.mkdir(parents=True)
            xml = '<xkbConfigRegistry><layoutList><layout><configItem><name>us</name><description>English</description></configItem></layout>  </layoutList></xkbConfigRegistry>'
            for name in ('evdev.xml', 'base.xml'):
                (rules / name).write_text(xml)
            user = root / 'config/xkb'
            installer.install_user(user, rules / 'evdev.xml')
            first = (user / 'rules/evdev.xml').read_text()
            installer.install_user(user, rules / 'evdev.xml')
            self.assertEqual(first, (user / 'rules/evdev.xml').read_text())
            layouts = ET.fromstring(first).findall('./layoutList/layout/configItem/name')
            self.assertEqual(['us', 'mxmini'], [item.text for item in layouts])
            self.assertTrue((user / 'symbols/mxmini').read_text().startswith(installer.MARKER))

    def test_unmanaged_symbols_are_not_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / 'symbols/mxmini'
            target.parent.mkdir(parents=True)
            target.write_text('unrelated custom layout')
            with self.assertRaises(RuntimeError):
                installer.install_user(root)
            self.assertEqual('unrelated custom layout', target.read_text())

    def test_fcitx_add_preserves_existing_layouts_and_default(self):
        class Reply:
            def __init__(self, value): self.value = value
            def unpack(self): return self.value
        class Bus:
            entries = [('keyboard-br', ''), ('keyboard-us', '')]
            def call_sync(self, dest, path, iface, method, params, *rest):
                if method == 'AvailableInputMethods': return Reply(([(installer.IM,)],))
                if method == 'CurrentInputMethodGroup': return Reply(('Default',))
                if method == 'InputMethodGroupInfo': return Reply(('us', self.entries))
                if method == 'SetInputMethodGroupInfo':
                    group, default, self.entries = params[1]
                    self.check = (group, default)
                    return Reply(())
                if method == 'Save': return Reply(())
                raise AssertionError(method)
        bus = Bus()
        gio = types.SimpleNamespace(bus_get_sync=lambda *args: bus, BusType=types.SimpleNamespace(SESSION=0), DBusCallFlags=types.SimpleNamespace(NONE=0))
        glib = types.SimpleNamespace(Variant=lambda *args: args, Error=type('GLibError', (Exception,), {}))
        modules = {'gi': types.ModuleType('gi'), 'gi.repository': types.SimpleNamespace(Gio=gio, GLib=glib)}
        with patch.dict(sys.modules, modules):
            installer.fcitx_add()
            installer.fcitx_add()
        self.assertEqual(('Default', 'us'), bus.check)
        self.assertEqual([('keyboard-br', ''), ('keyboard-us', ''), (installer.IM, installer.BACKING_LAYOUT)], bus.entries)

    def test_xkb_compiles_to_printed_us_keys_and_cedilla(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'symbols').mkdir()
            (root / 'symbols/mxmini').write_text(installer.SYMBOLS.read_text())
            map_file = root / 'map.xkb'
            compiled = root / 'compiled.xkb'
            with map_file.open('w') as output:
                subprocess.run(['setxkbmap', '-I' + str(root), '-layout', 'mxmini', '-print'], stdout=output, check=True)
            subprocess.run(['xkbcomp', '-I' + str(root), '-I/usr/share/X11/xkb', '-w', '0', '-xkb', str(map_file), str(compiled)], check=True)
            text = compiled.read_text()
            self.assertIn('MX Keys Mini For Mac - en-us', text)
            self.assertRegex(text, r'key <TLDE>\s*\{\s*\[\s*grave,\s*asciitilde')
            self.assertRegex(text, r'key <AE01>\s*\{\s*\[\s*1,\s*exclam')
            self.assertRegex(text, r'key <AB08>\s*\{[^}]*comma,\s*less,\s*ccedilla,\s*Ccedilla')
            us_map = root / 'us.xkb'
            us_output = root / 'us-compiled.xkb'
            with us_map.open('w') as output:
                subprocess.run(['setxkbmap', '-layout', 'us', '-print'], stdout=output, check=True)
            subprocess.run(['xkbcomp', '-I/usr/share/X11/xkb', '-w', '0', '-xkb', str(us_map), str(us_output)], check=True)
            baseline = us_output.read_text()
            with us_map.open('w') as output:
                subprocess.run(['setxkbmap', '-layout', 'us', '-variant', 'altgr-intl', '-print'], stdout=output, check=True)
            subprocess.run(['xkbcomp', '-I/usr/share/X11/xkb', '-w', '0', '-xkb', str(us_map), str(us_output)], check=True)
            backing = us_output.read_text()
            self.assertRegex(backing, r'key <AB08>\s*\{[^}]*comma,\s*less,\s*ccedilla,\s*Ccedilla')
            def levels(source, code):
                key = re.search(r'key <' + code + r'>\s*\{([^}]+)\}', source)
                self.assertIsNotNone(key, code)
                symbols = re.findall(r'\[([^]]+)\]', key.group(1))
                self.assertTrue(symbols, code)
                return [value.strip() for value in symbols[-1].split(',')][:2]
            names = ['TLDE', 'BKSL'] + [f'AE{i:02}' for i in range(1, 13)] + [f'AD{i:02}' for i in range(1, 13)] + [f'AC{i:02}' for i in range(1, 12)] + [f'AB{i:02}' for i in range(1, 11)]
            for code in names:
                with self.subTest(key=code):
                    self.assertEqual(levels(baseline, code), levels(text, code))
                    self.assertEqual(levels(baseline, code), levels(backing, code))


if __name__ == '__main__':
    unittest.main()
