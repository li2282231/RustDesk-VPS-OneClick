"""Exercise the real installer functions with isolated APT/Docker substitutes.

No root, network access, package changes, or writes to /etc or /opt are needed.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
FRONTEND_LOCK = (
    "E: Could not get lock /var/lib/dpkg/lock-frontend. "
    "It is held by process 8537 (unattended-upgr)\n"
    "E: Unable to acquire the dpkg frontend lock, is another process using it?\n"
)
LISTS_LOCK = (
    "E: Could not get lock /var/lib/apt/lists/lock - open (11: Resource temporarily unavailable)\n"
    "E: Unable to lock directory /var/lib/apt/lists/\n"
)
ARCHIVES_LOCK = "E: Unable to lock directory /var/cache/apt/archives/\n"
TLS_ERROR = "E: Failed to fetch https://download.docker.com/ InRelease Could not handshake\n"

FAKE_APT = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

root = Path(os.environ["TEST_ROOT"])
log = root / "calls.jsonl"
calls = log.read_text().splitlines() if log.exists() else []
outcomes = json.loads(os.environ["APT_OUTCOMES"])
outcome = outcomes[min(len(calls), len(outcomes) - 1)]
source = root / "etc/apt/sources.list.d/docker.sources"
with log.open("a") as stream:
    stream.write(json.dumps({
        "args": sys.argv[1:],
        "locale": os.environ.get("LC_ALL"),
        "frontend": os.environ.get("DEBIAN_FRONTEND"),
        "source": source.read_text() if source.exists() else "",
    }) + "\n")
print(outcome.get("output", ""), end="", flush=True)
status = outcome.get("status", 0)
if status == 0 and "install" in sys.argv:
    if "docker-ce" in sys.argv:
        (root / "docker-installed").touch()
    if "docker-compose-plugin" in sys.argv:
        (root / "compose-installed").touch()
sys.exit(status)
'''

FAKE_CURL = r'''#!/usr/bin/env python3
from pathlib import Path
import sys
Path(sys.argv[sys.argv.index("-o") + 1]).write_text("test public key")
'''

FAKE_DOCKER = r'''#!/usr/bin/env bash
[[ -f "${TEST_ROOT}/docker-installed" ]] || exit 1
if [[ "$*" == 'compose version' ]]; then
    [[ -f "${TEST_ROOT}/compose-installed" ]]
fi
'''


class AptLockTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.root / "etc/apt/sources.list.d").mkdir(parents=True)
        self.installer = self.root / "install.sh"
        # Redirect only fixture paths; the wrapper and installation logic stay intact.
        self.installer.write_text(
            (REPO / "install.sh").read_text()
            .replace("/etc/apt/", str(self.root / "etc/apt") + "/")
            .replace('readonly INSTALL_DIR="/opt/rustdesk"',
                     'readonly INSTALL_DIR="' + str(self.root / "opt/rustdesk") + '"')
        )
        for name, body in {
            "apt-get": FAKE_APT,
            "curl": FAKE_CURL,
            "gpg": "#!/usr/bin/env bash\nprintf 'fpr:::::::::9DC858229FC7DD38854AE2D88D81803C0EBFCD88:\\n'\n",
            "docker": FAKE_DOCKER,
            "systemctl": "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"${TEST_ROOT}/services.log\"\n",
        }.items():
            path = self.bin / name
            path.write_text(body.replace("#!/usr/bin/env python3", "#!" + sys.executable))
            path.chmod(0o755)

    def run_shell(self, body, outcomes=None, timeout="2"):
        env = dict(os.environ)
        env.update({
            "PATH": str(self.bin) + os.pathsep + env.get("PATH", "/usr/bin:/bin"),
            "TEST_ROOT": str(self.root),
            "APT_OUTCOMES": json.dumps(outcomes or [{}]),
            "APT_LOCK_TIMEOUT": timeout,
            "LC_ALL": "C",
        })
        return subprocess.run(
            ["bash", "-c", 'source "$1"\n' + body, "test", str(self.installer)],
            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=20,
        )

    def calls(self):
        log = self.root / "calls.jsonl"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_sourcing_does_not_start_installation(self):
        self.assert_success(self.run_shell(":"))
        self.assertEqual(self.calls(), [])

    def test_uncontended_install_preserves_arguments(self):
        self.assert_success(self.run_shell("apt_get install -y docker-ce docker-compose-plugin"))
        self.assertEqual(self.calls()[0]["args"], [
            "-o", "DPkg::Lock::Timeout=2", "install", "-y", "docker-ce", "docker-compose-plugin",
        ])

    def test_frontend_lock_is_retried_until_success(self):
        result = self.run_shell("apt_get install -y docker-ce", [
            {"status": 100, "output": FRONTEND_LOCK}, {},
        ])
        self.assert_success(result)
        self.assertEqual(len(self.calls()), 2)
        self.assertIn("等待后重试", result.stderr)
        self.assertEqual(self.calls()[1]["args"][1], "DPkg::Lock::Timeout=0")

    def test_lists_lock_is_retried_for_update(self):
        result = self.run_shell("apt_get update", [
            {"status": 100, "output": LISTS_LOCK}, {},
        ])
        self.assert_success(result)
        self.assertEqual(len(self.calls()), 2)
        self.assertIn("等待后重试", result.stderr)

    def test_archive_lock_is_retried(self):
        self.assert_success(self.run_shell("apt_get install -y curl", [
            {"status": 100, "output": ARCHIVES_LOCK}, {},
        ]))
        self.assertEqual(len(self.calls()), 2)

    def test_persistent_lock_times_out_and_cleans_temporary_log(self):
        log_dir = self.root / "tmp"
        log_dir.mkdir()
        result = self.run_shell('export TMPDIR="${TEST_ROOT}/tmp"; apt_get update', [
            {"status": 100, "output": LISTS_LOCK},
        ], timeout="1")
        self.assertEqual(result.returncode, 75, result.stdout + result.stderr)
        self.assertGreaterEqual(len(self.calls()), 1)
        self.assertLessEqual(len(self.calls()), 2)
        self.assertIn("已超时", result.stderr)
        self.assertEqual(list(log_dir.glob("rustdesk-apt.*")), [])

    def test_zero_timeout_fails_without_retry(self):
        result = self.run_shell("apt_get install -y curl", [
            {"status": 100, "output": FRONTEND_LOCK},
        ], timeout="0")
        self.assertEqual(result.returncode, 75)
        self.assertEqual(len(self.calls()), 1)

    def test_non_lock_errors_preserve_status_and_do_not_retry(self):
        result = self.run_shell("apt_get update", [{"status": 100, "output": TLS_ERROR}])
        self.assertEqual(result.returncode, 100)
        self.assertEqual(len(self.calls()), 1)
        self.assertNotIn("等待后重试", result.stderr)

    def test_apt_locale_does_not_depend_on_parent_locale(self):
        self.assert_success(self.run_shell("export LC_ALL=POSIX; apt_get update"))
        self.assertEqual(self.calls()[0]["locale"], "C")

    def test_invalid_timeout_fails_before_apt(self):
        for value in ["-1", "abc", "01", "86401", "999999999999999999999"]:
            with self.subTest(value=value):
                result = self.run_shell("apt_get update", timeout=value)
                self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_clean_install_handles_late_lock_and_mirror_fallback(self):
        result = self.run_shell('''
OS_ID=ubuntu
OS_CODENAME=jammy
ARCH=amd64
command() {
    if [[ "$*" == '-v docker' && ! -f "${TEST_ROOT}/docker-installed" ]]; then
        return 1
    fi
    builtin command "$@"
}
install_prerequisites
install_docker
''', [{}, {}, {"status": 100, "output": TLS_ERROR},
      {"status": 100, "output": LISTS_LOCK}, {},
      {"status": 100, "output": FRONTEND_LOCK}, {}])
        self.assert_success(result)
        calls = self.calls()
        self.assertEqual(len(calls), 7)
        self.assertEqual(calls[0]["args"][-1], "update")
        self.assertIn("ca-certificates", calls[1]["args"])
        self.assertIn("download.docker.com", calls[2]["source"])
        self.assertIn("mirrors.aliyun.com", calls[3]["source"])
        self.assertIn("mirrors.aliyun.com", calls[4]["source"])
        self.assertIn("docker-ce", calls[5]["args"])
        self.assertIn("docker-ce", calls[6]["args"])
        self.assertTrue(all(call["frontend"] == "noninteractive" for call in calls))
        self.assertEqual((self.root / "services.log").read_text(), "enable --now docker\n")

    def test_repository_lock_timeout_does_not_try_another_mirror(self):
        result = self.run_shell("OS_ID=ubuntu; OS_CODENAME=jammy; ARCH=amd64; configure_docker_repository", [
            {"status": 100, "output": LISTS_LOCK},
        ], timeout="0")
        self.assertEqual(result.returncode, 75, result.stdout + result.stderr)
        self.assertEqual(len(self.calls()), 1)
        self.assertNotIn("将尝试下一个软件源", result.stderr)
        self.assertNotIn("所有可信 Docker 软件源均无法使用", result.stderr)

    def test_existing_docker_only_installs_missing_compose(self):
        (self.root / "docker-installed").touch()
        result = self.run_shell("OS_ID=debian; OS_CODENAME=bookworm; ARCH=arm64; install_docker")
        self.assert_success(result)
        self.assertEqual(self.calls()[-1]["args"][-3:], ["install", "-y", "docker-compose-plugin"])
        self.assertIn("bookworm", self.calls()[0]["source"])

    def test_existing_docker_and_compose_skip_apt(self):
        (self.root / "docker-installed").touch()
        (self.root / "compose-installed").touch()
        self.assert_success(self.run_shell("install_docker"))
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
