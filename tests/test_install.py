"""Exercise both installer branches without downloads or host configuration edits."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest


INSTALLER = Path(__file__).resolve().parents[1] / "install.sh"
BASH = shutil.which("bash")
HERDR = shutil.which("herdr")


class InstallerTests(unittest.TestCase):
    def setup_home(self, system, login_file=None):
        root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.home = root / "home with spaces"
        self.bin = root / "bin"
        self.prefix = root / "brew"
        for directory in (self.home, self.bin, self.prefix / "bin"):
            directory.mkdir(parents=True)
        # Restrict discovery to fixture tools, but run the real portable utilities.
        for tool in ("bash", "sh", "mkdir", "dirname", "date", "tr", "cat", "cp",
                     "rm", "sed", "sort", "tail", "basename", "mktemp", "grep",
                     "cmp", "chmod", "jq"):
            real = shutil.which(tool)
            if not real:
                self.skipTest(f"{tool} is required for integration checks")
            (self.bin / tool).symlink_to(real)
        self.stub("uname", f"printf '%s\\n' {system}\n")
        for tool in ("ghostty", "git"):
            self.stub(tool, "exit 0\n")
        self.stub("fc-list", "echo 'JetBrainsMono Nerd'\n")
        self.stub("starship", "echo '_DEV_SETUP_STARSHIP_READY=1'\n")
        # Downloads must never happen in these all-present fixtures.
        self.stub("curl", "echo 'Unexpected download' >&2; exit 99\n")
        self.stub("herdr", '''
printf '%s\\n' "$*" >> "$HOME/herdr-calls"
if [ "${TEST_CHECK_GUI:-}" = 1 ]; then
  printf '%s\\n' "$SHELL" "$(command -v starship)" > "$HOME/gui-environment"
fi
if [ "${1:-} ${2:-}" = 'config check' ] && [ -n "$TEST_REAL_HERDR" ]; then
  HERDR_CONFIG_PATH="$HOME/.config/herdr/config.toml" "$TEST_REAL_HERDR" config check
fi
if [ "${1:-} ${2:-}" = 'tab list' ]; then
  printf '%s\\n' '{"result":{"tabs":[]}}'
fi
if [ "${2:-}" = close ]; then exit "${TEST_CLOSE_STATUS:-0}"; fi
''')
        self.stub("brew", '''
printf '%s\\n' "$*" >> "$HOME/brew-calls"
case "$1" in
  shellenv) printf 'export PATH="%s/bin:$PATH"\\n' "$TEST_BREW_PREFIX" ;;
  --prefix) printf '%s\\n' "$TEST_BREW_PREFIX" ;;
  install)
    case "$2" in
      bash) ln -s "$TEST_REAL_BASH" "$TEST_BREW_PREFIX/bin/bash" ;;
      *) echo "Unexpected brew install: $*" >&2; exit 99 ;;
    esac ;;
esac
''')
        (self.bin / "ln").symlink_to(shutil.which("ln"))
        font = self.home / "Library/Fonts/JetBrainsMonoNerdFont-Regular.ttf"
        font.parent.mkdir(parents=True)
        font.touch()  # /Library/Fonts may be missing: this must still count.
        gvm = self.home / ".gvm"
        (gvm / "scripts").mkdir(parents=True)
        (gvm / "environments").mkdir()
        go = gvm / "gos/go1.24.6/bin/go"
        go.parent.mkdir(parents=True)
        go.write_text("#!/bin/sh\necho 'go version go1.24.6'\n")
        go.chmod(0o755)
        (gvm / "environments/default").write_text('''
export GOROOT="$HOME/.gvm/gos/go1.24.6"
export PATH="$GOROOT/bin:$PATH"
gvm_go_name=go1.24.6
''')
        (gvm / "scripts/gvm").write_text('''
gvm() { :; }
source "$HOME/.gvm/environments/default"
''')
        self.original_rc = "# user settings\nexport USER_SETTING=preserved\n"
        (self.home / ".bashrc").write_text(self.original_rc)
        if login_file:
            (self.home / login_file).write_text(
                'export LOGIN_SETTING=preserved\n'
                '[[ ! -r "$HOME/.bashrc" ]] || source "$HOME/.bashrc"\n')
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin),
                        TEST_BREW_PREFIX=str(self.prefix), TEST_REAL_BASH=BASH,
                        TEST_REAL_HERDR=HERDR or "",
                        DEV_SETUP_SKIP_KEYBOARD="1",
                        TERM="dumb")
        for key in ("BASH_ENV", "ENV", "DEV_SETUP_GO_VERSION", "HERDR_CONFIG_PATH",
                    "HERDR_TAB_ID", "HERDR_WORKSPACE_ID"):
            self.env.pop(key, None)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\nset -eu\n" + body)
        path.chmod(0o755)

    def run_installer(self):
        result = subprocess.run([BASH, str(INSTALLER)], env=self.env,
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return tomllib.loads((self.home / ".config/herdr/config.toml").read_text())

    def verify_startup(self, login=False):
        rc = ".bash_profile" if login else ".bashrc"
        # Source under an interactive shell to check managed startup loading.
        result = subprocess.run([BASH, "--noprofile", "--norc", "-ic", f'''
source "$HOME/{rc}"
[[ $USER_SETTING == preserved ]] || exit 81
[[ {'$LOGIN_SETTING == preserved' if login else '1 == 1'} ]] || exit 82
declare -F gvm >/dev/null || exit 83
go version
'''], env=self.env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("go version go1.24.6", result.stdout)

    def verify_rerun(self):
        paths = [self.home / ".bashrc", self.home / ".bash_profile"]
        before = {p: p.read_bytes() for p in paths if p.exists()}
        self.run_installer()
        for path, content in before.items():
            self.assertEqual(path.read_bytes(), content, f"Rerun changed {path.name}")
        backups = list((self.home / ".config/dev-setup-backup").glob("*/.bashrc"))
        self.assertTrue(backups)
        self.assertTrue(any(p.read_text() == self.original_rc for p in backups))

    def test_linux(self):
        self.setup_home("Linux")
        config = self.run_installer()
        self.assertEqual(config["keys"]["prefix"], "ctrl+w")
        self.assertEqual(config["keys"]["clear_pane"], "ctrl+k")
        self.assertEqual(config["terminal"]["shell_mode"], "non_login")
        self.assertFalse((self.home / ".bash_profile").exists())
        self.assertTrue((self.home / ".config/ghostty/config").exists())
        ghostty = (self.home / ".config/ghostty/config").read_text()
        self.assertIn("keybind = ctrl+w=unbind", ghostty)
        self.assertNotIn("macos-option", (self.home / ".config/ghostty/config").read_text())
        self.assertTrue(tomllib.loads((self.home / ".config/starship.toml").read_text())["golang"]["disabled"])
        self.verify_startup()
        self.verify_rerun()

    def test_mac_profile_migration(self):
        self.setup_home("Darwin", ".profile")
        config = self.run_installer()
        self.assertEqual(config["keys"]["prefix"], "cmd+w")
        self.assertEqual(config["keys"]["clear_pane"], "cmd+k")
        self.assertIn("cmd+shift+space", config["keys"]["copy_mode"])
        self.assertEqual(config["terminal"]["default_shell"], str(self.prefix / "bin/bash"))
        self.assertEqual(config["terminal"]["shell_mode"], "login")
        calls = (self.home / "brew-calls").read_text()
        self.assertIn("install bash\n", calls)
        self.assertNotIn("install --cask font", calls)
        ghostty = self.home / "Library/Application Support/com.mitchellh.ghostty/config.ghostty"
        self.assertIn("cmd+shift+left=csi:1;2H", ghostty.read_text())
        self.verify_startup(login=True)
        self.verify_rerun()

    def test_mac_existing_login_profile(self):
        self.setup_home("Darwin", ".bash_profile")
        self.run_installer()
        self.verify_startup(login=True)
        self.verify_rerun()

    def test_mac_gui_without_homebrew_on_path(self):
        self.setup_home("Darwin")
        self.run_installer()
        # A GUI launch knows neither brew nor its tools. The installed launcher
        # must restore their paths before starting the Herdr server.
        minimal = self.home / "gui-bin"
        minimal.mkdir()
        (minimal / "uname").symlink_to(self.bin / "uname")
        (self.bin / "starship").rename(self.prefix / "bin/starship")
        result = subprocess.run([str(self.home / ".config/herdr/launch.sh")],
                                env=dict(self.env, PATH=str(minimal), TEST_CHECK_GUI="1"),
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.home / "gui-environment").read_text().splitlines(),
                         [str(self.prefix / "bin/bash"), str(self.prefix / "bin/starship")])

    def test_close_popup_without_herdr_on_path(self):
        self.setup_home("Linux")
        config = self.run_installer()
        minimal = self.home / "popup-bin"
        minimal.mkdir()
        for tool in ("uname", "jq"):
            (minimal / tool).symlink_to(self.bin / tool)
        env = dict(self.env, PATH=str(minimal), HERDR_ACTIVE_TAB_ID="active-tab",
                   HERDR_ACTIVE_PANE_ID="active-pane", HERDR_ACTIVE_WORKSPACE_ID="active-ws",
                   HERDR_TAB_ID="wrong-tab", HERDR_PANE_ID="wrong-pane")
        for kind, key, target in (("tab", "prefix+shift+x", "active-tab"),
                                  ("pane", "prefix+x", "active-pane")):
            command = next(c["command"] for c in config["keys"]["command"] if c["key"] == key)
            # The popup can run sh, but cannot resolve herdr itself.
            (minimal / "sh").symlink_to(shutil.which("sh"))
            try:
                result = subprocess.run([shutil.which("sh"), "-c", command], env=env,
                                        input="y\n", text=True, capture_output=True, timeout=10)
            finally:
                (minimal / "sh").unlink()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            calls = (self.home / "herdr-calls").read_text()
            self.assertIn(f"{kind} close {target}\n", calls)
            self.assertIn("tab list --workspace active-ws\n", calls)
            self.assertNotIn("pane current", calls)

    def test_close_cancel_and_failure(self):
        self.setup_home("Linux")
        self.run_installer()
        script = self.home / ".config/herdr/close.sh"
        env = dict(self.env, HERDR_ACTIVE_TAB_ID="active-tab")
        for answer in ("n\n", "\n", ""):
            result = subprocess.run([shutil.which("sh"), str(script), "tab"], env=env,
                                    input=answer, text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("tab close", (self.home / "herdr-calls").read_text())
        result = subprocess.run([shutil.which("sh"), str(script), "tab"],
                                env=dict(env, TEST_CLOSE_STATUS="7"), input="y\n",
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 7, "Close errors must still be reported")


if __name__ == "__main__":
    unittest.main()
