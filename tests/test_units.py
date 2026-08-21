#!/usr/bin/env python3
"""unittest suite for units.py using stub overrides."""
import json
import os
import sys
import tempfile
import unittest

# Point at the project root so we can import units.py
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

# Point at stubs dir
STUBS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stubs")
CANNED_DIR = os.path.join(STUBS_DIR, "canned")

import units


def _run_units(*cli_args):
    """Run units.main() in-process, capture output, return (json_dict, exit_code)."""
    sys.argv = ["units.py"] + list(cli_args)
    old_stdout = sys.stdout
    old_stderr = sys.stderr
    sys.stdout = buf = __import__("io").StringIO()
    sys.stderr = __import__("io").StringIO()
    exit_code = 0
    try:
        units.main()
    except SystemExit as e:
        exit_code = e.code
    finally:
        out = buf.getvalue()
        sys.stdout = old_stdout
        sys.stderr = old_stderr
    return json.loads(out), exit_code


def _clean_pkexec_record():
    path = os.path.join(CANNED_DIR, ".pkexec_invocation.txt")
    if os.path.exists(path):
        os.unlink(path)


def _pkexec_invoked():
    path = os.path.join(CANNED_DIR, ".pkexec_invocation.txt")
    return os.path.exists(path)


def setUpModule():
    os.environ["OSYSTEMD_SYSTEMCTL"] = os.path.join(STUBS_DIR, "systemctl.py")
    os.environ["OSYSTEMD_JOURNALCTL"] = os.path.join(STUBS_DIR, "journalctl.py")
    os.environ["OSYSTEMD_PKEXEC"] = os.path.join(STUBS_DIR, "pkexec.py")


class TestList(unittest.TestCase):
    def setUp(self):
        _clean_pkexec_record()

    def test_list_user_parses_units(self):
        data, ec = _run_units("list", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        self.assertEqual(data["scope"], "user")
        units_list = data["data"]["units"]
        self.assertGreater(len(units_list), 0)
        # Check first unit has expected fields
        u = units_list[0]
        self.assertIn("name", u)
        self.assertIn("type", u)
        self.assertIn("active", u)
        self.assertIn("sub", u)
        self.assertIn("description", u)

    def test_list_description_with_spaces(self):
        data, ec = _run_units("list", "--scope", "user")
        units_list = data["data"]["units"]
        # "OpenBSD Secure Shell server daemon" should be preserved
        names = [u["name"] for u in units_list]
        self.assertIn("ssh.service", names)
        ssh = next(u for u in units_list if u["name"] == "ssh.service")
        self.assertIn("OpenBSD", ssh["description"])
        self.assertIn("server", ssh["description"])
        self.assertIn("daemon", ssh["description"])

    def test_list_type_derived_from_suffix(self):
        data, ec = _run_units("list", "--scope", "user")
        units_list = data["data"]["units"]
        timers = [u for u in units_list if u["type"] == "timer"]
        mounts = [u for u in units_list if u["type"] == "mount"]
        self.assertGreater(len(timers), 0)
        self.assertGreater(len(mounts), 0)

    def test_list_type_filter(self):
        """Verify that --types passes --type= flag to systemctl."""
        data, ec = _run_units("list", "--scope", "user", "--types", "timer")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        # The canned output includes timers, so we should get some
        units_list = data["data"]["units"]
        # All returned units should be of type timer
        for u in units_list:
            self.assertEqual(u["type"], "timer")

    def test_list_state_filter(self):
        """Verify that --states passes --state= flag to systemctl."""
        data, ec = _run_units("list", "--scope", "user", "--states", "failed")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        units_list = data["data"]["units"]
        # All returned units should be failed
        for u in units_list:
            self.assertEqual(u["active"], "failed")

    def test_list_filter_substring(self):
        data, ec = _run_units("list", "--scope", "user", "--filter", "ssh")
        self.assertEqual(ec, 0)
        units_list = data["data"]["units"]
        names = [u["name"] for u in units_list]
        self.assertIn("ssh.service", names)

    def test_list_system(self):
        data, ec = _run_units("list", "--scope", "system")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        self.assertEqual(data["scope"], "system")


class TestStatus(unittest.TestCase):
    def setUp(self):
        _clean_pkexec_record()

    def test_status_returns_curated_fields(self):
        data, ec = _run_units("status", "ssh.service", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        d = data["data"]
        self.assertEqual(d["unit"], "ssh.service")
        self.assertEqual(d["LoadState"], "loaded")
        self.assertEqual(d["ActiveState"], "active")
        self.assertEqual(d["SubState"], "running")
        self.assertEqual(d["Description"], "OpenBSD Secure Shell server daemon")
        self.assertEqual(d["MainPID"], "1234")

    def test_status_missing_unit(self):
        data, ec = _run_units("status", "--scope", "user")
        self.assertEqual(ec, 2)
        self.assertFalse(data["ok"])
        self.assertEqual(data["error"]["code"], "usage")


class TestShow(unittest.TestCase):
    def test_show_returns_all_properties(self):
        data, ec = _run_units("show", "ssh.service", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        props = data["data"]["properties"]
        self.assertIn("LoadState", props)
        self.assertIn("MainPID", props)
        self.assertIn("Restart", props)


class TestCat(unittest.TestCase):
    def test_cat_returns_raw_and_files(self):
        data, ec = _run_units("cat", "ssh.service", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        d = data["data"]
        self.assertIn("raw", d)
        self.assertIn("files", d)
        self.assertGreater(len(d["files"]), 0)
        self.assertEqual(d["files"][0]["path"], "/usr/lib/systemd/system/ssh.service")
        self.assertIn("[Unit]", d["files"][0]["content"])


class TestJournal(unittest.TestCase):
    def test_journal_returns_lines(self):
        data, ec = _run_units("journal", "ssh.service", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        lines = data["data"]["lines"]
        self.assertGreater(len(lines), 0)
        self.assertIn("sshd", lines[0])

    def test_journal_lines_cap(self):
        data, ec = _run_units("journal", "ssh.service", "--scope", "user", "--lines", "2")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])


class TestMutations(unittest.TestCase):
    def setUp(self):
        _clean_pkexec_record()

    def test_user_start_no_pkexec(self):
        _clean_pkexec_record()
        data, ec = _run_units("start", "nginx.service", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        self.assertFalse(_pkexec_invoked())

    def test_system_start_uses_pkexec(self):
        _clean_pkexec_record()
        data, ec = _run_units("start", "nginx.service", "--scope", "system")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        self.assertTrue(_pkexec_invoked())

    def test_system_stop_uses_pkexec(self):
        _clean_pkexec_record()
        data, ec = _run_units("stop", "nginx.service", "--scope", "system")
        self.assertEqual(ec, 0)
        self.assertTrue(_pkexec_invoked())

    def test_system_restart_uses_pkexec(self):
        _clean_pkexec_record()
        data, ec = _run_units("restart", "nginx.service", "--scope", "system")
        self.assertEqual(ec, 0)
        self.assertTrue(_pkexec_invoked())

    def test_system_enable_uses_pkexec(self):
        _clean_pkexec_record()
        data, ec = _run_units("enable", "nginx.service", "--scope", "system")
        self.assertEqual(ec, 0)
        self.assertTrue(_pkexec_invoked())

    def test_system_disable_uses_pkexec(self):
        _clean_pkexec_record()
        data, ec = _run_units("disable", "nginx.service", "--scope", "system")
        self.assertEqual(ec, 0)
        self.assertTrue(_pkexec_invoked())

    def test_system_mask_uses_pkexec(self):
        _clean_pkexec_record()
        data, ec = _run_units("mask", "nginx.service", "--scope", "system")
        self.assertEqual(ec, 0)
        self.assertTrue(_pkexec_invoked())

    def test_system_unmask_uses_pkexec(self):
        _clean_pkexec_record()
        data, ec = _run_units("unmask", "nginx.service", "--scope", "system")
        self.assertEqual(ec, 0)
        self.assertTrue(_pkexec_invoked())

    def test_system_readonly_no_pkexec(self):
        """System read-only (status) should NOT use pkexec."""
        _clean_pkexec_record()
        data, ec = _run_units("status", "ssh.service", "--scope", "system")
        self.assertEqual(ec, 0)
        self.assertFalse(_pkexec_invoked())

    def test_user_enable_no_pkexec(self):
        _clean_pkexec_record()
        data, ec = _run_units("enable", "nginx.service", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertFalse(_pkexec_invoked())


class TestDaemonReload(unittest.TestCase):
    def setUp(self):
        _clean_pkexec_record()

    def test_daemon_reload_system_uses_pkexec(self):
        _clean_pkexec_record()
        data, ec = _run_units("daemon-reload", "--scope", "system")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        self.assertTrue(_pkexec_invoked())

    def test_daemon_reload_user_no_pkexec(self):
        _clean_pkexec_record()
        data, ec = _run_units("daemon-reload", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        self.assertFalse(_pkexec_invoked())


class TestErrorHandling(unittest.TestCase):
    def setUp(self):
        _clean_pkexec_record()

    def test_bad_args_returns_usage(self):
        """No --scope should give exit code 2 + usage."""
        data, ec = _run_units("list")
        self.assertEqual(ec, 2)
        self.assertFalse(data["ok"])
        self.assertEqual(data["error"]["code"], "usage")

    def test_bad_command_returns_usage(self):
        data, ec = _run_units("nonexistent", "--scope", "user")
        self.assertEqual(ec, 2)
        self.assertFalse(data["ok"])
        self.assertEqual(data["error"]["code"], "usage")

    def test_missing_binary(self):
        """Point at a nonexistent binary to test binary_missing."""
        old = os.environ.get("OSYSTEMD_SYSTEMCTL")
        os.environ["OSYSTEMD_SYSTEMCTL"] = "/nonexistent/systemctl"
        try:
            data, ec = _run_units("list", "--scope", "user")
            self.assertEqual(ec, 3)
            self.assertFalse(data["ok"])
            self.assertEqual(data["error"]["code"], "binary_missing")
        finally:
            if old is not None:
                os.environ["OSYSTEMD_SYSTEMCTL"] = old
            else:
                del os.environ["OSYSTEMD_SYSTEMCTL"]


class TestDiagnose(unittest.TestCase):
    def test_diagnose_returns_capability_summary(self):
        data, ec = _run_units("diagnose")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        d = data["data"]
        self.assertIn("pythonVersion", d)
        self.assertIn("helperVersion", d)
        self.assertEqual(d["helperVersion"], "0.2.0")
        self.assertIn("systemctl", d)
        self.assertIn("journalctl", d)
        self.assertIn("pkexec", d)
        self.assertIn("canElevate", d)
        self.assertIn("scopeUser", d)
        self.assertIn("scopeSystem", d)
        # systemctl should be found since our stub exists
        self.assertTrue(d["systemctl"])
        self.assertTrue(d["journalctl"])


if __name__ == "__main__":
    unittest.main()
