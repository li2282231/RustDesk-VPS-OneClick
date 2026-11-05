"""Linux-only checks using real APT and POSIX locks in a temporary APT tree.

Uses empty package lists/status and no repositories. Never changes host packages.
"""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform.startswith("linux") and shutil.which("apt-get"),
                     "requires Linux APT")
class RealAptLockTests(unittest.TestCase):
    def setUp(self):
        import fcntl
        self.fcntl = fcntl
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ["etc/apt.conf.d", "etc/sources.list.d", "state/dpkg",
                          "state/lists/partial", "cache/archives/partial"]:
            (self.root / directory).mkdir(parents=True)
        (self.root / "state/dpkg/status").touch()
        (self.root / "etc/sources.list").touch()
        config = self.root / "apt.conf"
        config.write_text('''
Dir::Etc "ROOT/etc";
Dir::State "ROOT/state";
Dir::State::status "ROOT/state/dpkg/status";
Dir::State::lists "ROOT/state/lists";
Dir::Cache "ROOT/cache";
Dir::Cache::archives "ROOT/cache/archives";
Dir::Log "ROOT/log";
APT::Get::List-Cleanup "false";
'''.replace("ROOT", str(self.root)))
        self.env = dict(os.environ, APT_CONFIG=str(config), APT_LOCK_TIMEOUT="2", LC_ALL="C")

    def hold_lock(self, relative):
        stream = (self.root / relative).open("w")
        self.addCleanup(stream.close)
        self.fcntl.lockf(stream, self.fcntl.LOCK_EX | self.fcntl.LOCK_NB)
        return stream

    def start_apt(self, operation, timeout="2"):
        env = dict(self.env, APT_LOCK_TIMEOUT=timeout)
        return subprocess.Popen(
            ["bash", "-c", 'source "$1"; apt_get "$2"', "test", str(REPO / "install.sh"), operation],
            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    def finish(self, process):
        try:
            stdout, stderr = process.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            self.fail("APT lock handling exceeded its test deadline")
        return stdout + stderr

    def test_real_lists_lock_times_out(self):
        self.hold_lock("state/lists/lock")
        process = self.start_apt("update", timeout="1")
        output = self.finish(process)
        self.assertEqual(process.returncode, 75, output)
        self.assertIn("已超时", output)

    def test_real_lists_lock_release_allows_update(self):
        stream = self.hold_lock("state/lists/lock")
        process = self.start_apt("update")
        time.sleep(0.5)
        self.fcntl.lockf(stream, self.fcntl.LOCK_UN)
        output = self.finish(process)
        self.assertEqual(process.returncode, 0, output)
        self.assertIn("等待后重试", output)

    def test_real_frontend_lock_uses_native_wait(self):
        stream = self.hold_lock("state/dpkg/lock-frontend")
        process = self.start_apt("install")
        time.sleep(0.5)
        self.assertIsNone(process.poll(), "APT did not wait for the frontend lock")
        self.fcntl.lockf(stream, self.fcntl.LOCK_UN)
        output = self.finish(process)
        self.assertEqual(process.returncode, 0, output)


if __name__ == "__main__":
    unittest.main()
