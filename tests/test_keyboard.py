"""Check profile generation without touching the live keyboard or system."""
import os
import json
import sys
import types
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'configure_keyboard.sh'


class KeyboardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SCRIPT.read_text().split("<<'PY'\n", 1)[1].rsplit('\ntry:\n    sys.exit(main()', 1)[0]
        cls.module = {}
        exec(compile(source, str(SCRIPT), 'exec'), cls.module)

    def test_deepin_keyd_executable_detection(self):
        with patch.object(self.module['shutil'], 'which', side_effect=lambda name: '/usr/bin/keyd.rvaiya' if name == 'keyd.rvaiya' else None):
            self.assertEqual('/usr/bin/keyd.rvaiya', self.module['keyd_command']())

    def test_deepin_profile_and_selection(self):
        profile = self.module['config'](['046d:b369'], 'alt', True)
        for mapping in ('leftalt = layer(mac_command)', 'space = C-M-space', 'q = A-f4',
                        '4 = C-A-a', 'backspace = delete', 'tab = swapm(mac_group_switch, A-grave)', 'left = S-home', 'right = S-end',
                        'up = S-C-home', 'down = S-C-end'):
            self.assertIn(mapping, profile)
        self.assertIn('[mac_command:C]', profile)
        self.assertNotIn('space = f13', profile)
        self.assertNotIn('grave = f24', profile)
        self.assertIn('tab = swapm(mac_app_switch, S-A-tab)', profile)
        self.assertIn('tab = swapm(mac_group_switch, S-A-grave)', profile)
        self.assertIn('space = C-S-space', profile)

    def test_connected_keyboard_command_and_option_mapping(self):
        profile = self.module['config'](['046d:b369'], 'alt', True)
        self.assertIn('leftalt = layer(mac_command)', profile)
        self.assertIn('leftmeta = layer(mac_option)', profile)
        self.assertIn('tab = swapm(mac_app_switch, A-tab)', profile)
        self.assertIn('tab = swapm(mac_group_switch, A-grave)', profile)

    def test_mac_mode_and_gnome_profile(self):
        profile = self.module['config'](['046d:b369'], 'meta')
        self.assertIn('leftmeta = layer(mac_command)', profile)
        self.assertIn('space = f13', profile)

    def test_legacy_acute_cleanup_preserves_other_mappings(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            state, script, desktop = root / 'state.json', root / 'acute.sh', root / 'acute.desktop'
            state.write_text('{"previous": "keycode 202 = F24"}')
            script.write_text('xmodmap -e "keycode 202 = acute acute acute"')
            desktop.write_text('# Managed by dev-setup keyboard acute key\n')
            calls = []
            with patch.dict(self.module, ACUTE_STATE=state, ACUTE_SCRIPT=script, ACUTE_DESKTOP=desktop), \
                 patch.dict(os.environ, DISPLAY=':0'), \
                 patch.object(self.module['shutil'], 'which', return_value='/usr/bin/xmodmap'), \
                 patch.dict(self.module, run=lambda args, **kwargs: calls.append(args) or subprocess.CompletedProcess(args, 0, 'keycode 202 = acute acute\n')):
                self.module['remove_legacy_acute']()
            self.assertEqual(calls[-1], ['xmodmap', '-e', 'keycode 202 = F24'])
            self.assertFalse(state.exists())
            self.assertFalse(desktop.exists())
            self.assertFalse(script.exists())

    def test_kwin_application_switcher_restores_previous_setting(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            config, state = root / 'kwinrc', root / 'state.json'
            original = '[Other]\nValue=keep\n\n[TabBox]\nApplicationsMode=0\nLayoutName=keep\n'
            config.write_text(original)
            with patch.dict(self.module, KWIN_CONFIG=config, KWIN_STATE=state, run=lambda *args, **kwargs: None):
                self.module['kwin_switcher'](True)
                self.module['kwin_switcher'](True)
                self.assertIn('ApplicationsMode=1\n', config.read_text())
                self.module['kwin_switcher'](False)
                self.assertEqual(original, config.read_text())
                self.assertFalse(state.exists())

    def test_live_search_rerun_handles_null_conflict_accelerators(self):
        shortcuts = [
            {'Id': 'globalSearch', 'Type': 0, 'Accels': ['<Control><Super>space']},
            {'Id': 'UOS AI Talk', 'Type': 1, 'Accels': None},
        ]
        calls = []
        class Reply:
            def unpack(self):
                return (json.dumps(shortcuts),)
        class Bus:
            def call_sync(self, *args):
                calls.append(args[3])
                return Reply()
        gio = types.SimpleNamespace(bus_get_sync=lambda *args: Bus(),
                                    BusType=types.SimpleNamespace(SESSION=0),
                                    DBusCallFlags=types.SimpleNamespace(NONE=0))
        glib = types.SimpleNamespace(Variant=lambda *args: args)
        modules = {'gi': types.ModuleType('gi'), 'gi.repository': types.SimpleNamespace(Gio=gio, GLib=glib)}
        with tempfile.TemporaryDirectory() as temp, patch.dict(sys.modules, modules):
            state = Path(temp) / 'state.json'
            state.write_text(json.dumps({'search': ['<Shift>space'], 'conflicts': [
                {'Id': 'UOS AI Talk', 'Type': 1, 'shortcut': '<Control><Super>space'}]}))
            with patch.dict(self.module, DEEPIN_LIVE_STATE=state):
                self.module['deepin_live_search'](True)
            self.assertEqual(calls, ['ListAllShortcuts'])
            self.assertTrue(state.exists())

    def test_ghostty_selection_is_idempotent_and_reversible(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, XDG_CONFIG_HOME=temp):
            path = Path(temp) / 'ghostty/config'
            path.parent.mkdir()
            path.write_text('font-size = 12\n')
            self.module['ghostty_selection'](True)
            first = path.read_text()
            self.assertIn('keybind = shift+home=unbind', first)
            self.module['ghostty_selection'](True)
            self.assertEqual(first, path.read_text())
            self.module['ghostty_selection'](False)
            self.assertEqual('font-size = 12\n', path.read_text())

    def test_revert_accepted_without_keyboard(self):
        # The parser must accept the requested positional argument; avoid executing sudo.
        result = subprocess.run(['bash', str(SCRIPT), 'revert', '--help'],
                                capture_output=True, text=True, env=dict(os.environ, XDG_CURRENT_DESKTOP='DDE'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('revert', result.stdout)


if __name__ == '__main__':
    unittest.main()
