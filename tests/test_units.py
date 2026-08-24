#!/usr/bin/env python3
"""unittest suite for units.py using stub overrides."""
import json
import os
import sys
import tempfile
import unittest
import unittest.mock

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


def setUpModule():
    os.environ["OSYSTEMD_SYSTEMCTL"] = os.path.join(STUBS_DIR, "systemctl.py")
    os.environ["OSYSTEMD_JOURNALCTL"] = os.path.join(STUBS_DIR, "journalctl.py")


class TestList(unittest.TestCase):
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

    def test_list_includes_unloaded_field(self):
        data, ec = _run_units("list", "--scope", "system")
        self.assertEqual(ec, 0)
        self.assertIn("unloaded", data["data"])
        self.assertIsInstance(data["data"]["unloaded"], list)
        self.assertGreater(len(data["data"]["unloaded"]), 0)

    def test_list_unloaded_excludes_loaded_units(self):
        data, ec = _run_units("list", "--scope", "system")
        self.assertEqual(ec, 0)
        loaded_names = {u["name"] for u in data["data"]["units"]}
        unloaded_names = {u["name"] for u in data["data"]["unloaded"]}
        # No overlap
        self.assertEqual(loaded_names & unloaded_names, set())
        # alsa-restore.service is in loaded, must NOT be in unloaded
        self.assertIn("alsa-restore.service", loaded_names)
        self.assertNotIn("alsa-restore.service", unloaded_names)

    def test_list_unloaded_fprintd_present(self):
        data, ec = _run_units("list", "--scope", "system")
        self.assertEqual(ec, 0)
        unloaded_names = [u["name"] for u in data["data"]["unloaded"]]
        self.assertIn("fprintd.service", unloaded_names)

    def test_list_unloaded_uses_correct_shape(self):
        data, ec = _run_units("list", "--scope", "system")
        self.assertEqual(ec, 0)
        for item in data["data"]["unloaded"]:
            self.assertIn("name", item)
            self.assertIn("type", item)
            self.assertIn("fileState", item)
            self.assertIn("preset", item)

    def test_list_unloaded_type_filter(self):
        data, ec = _run_units("list", "--scope", "system", "--types", "service")
        self.assertEqual(ec, 0)
        # fprintd is a service, should still be in unloaded
        unloaded_names = [u["name"] for u in data["data"]["unloaded"]]
        self.assertIn("fprintd.service", unloaded_names)

    def test_list_unloaded_state_filter(self):
        data, ec = _run_units("list", "--scope", "system", "--states", "static")
        self.assertEqual(ec, 0)
        # Only static units should appear in unloaded
        for item in data["data"]["unloaded"]:
            self.assertEqual(item["fileState"], "static")
        unloaded_names = [u["name"] for u in data["data"]["unloaded"]]
        self.assertIn("fprintd.service", unloaded_names)
        self.assertIn("cron.service", unloaded_names)

    def test_list_unloaded_does_not_fail_when_list_unit_files_missing(self):
        """list --scope user still returns ok with unloaded=[] if list-unit-files fails."""
        old = os.environ.get("OSYSTEMD_SYSTEMCTL")
        # Use a custom stub that succeeds on list-units but fails on list-unit-files
        stub_path = os.path.join(STUBS_DIR, "systemctl_partial_fail.py")
        try:
            os.environ["OSYSTEMD_SYSTEMCTL"] = stub_path
            data, ec = _run_units("list", "--scope", "user")
            self.assertEqual(ec, 0)
            self.assertTrue(data["ok"])
            self.assertIn("unloaded", data["data"])
            self.assertEqual(data["data"]["unloaded"], [])
        finally:
            if old is not None:
                os.environ["OSYSTEMD_SYSTEMCTL"] = old
            else:
                del os.environ["OSYSTEMD_SYSTEMCTL"]


class TestStatus(unittest.TestCase):
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
    def test_user_start_succeeds(self):
        data, ec = _run_units("start", "nginx.service", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])

    def _assert_invokes_systemctl_not_pkexec(self, mock_run, scope):
        """Assert the first command element is the systemctl stub, not pkexec."""
        called_cmd = mock_run.call_args[0][0]
        # The first element must be the systemctl binary (stub path in tests),
        # not a pkexec wrapper.
        self.assertNotEqual(called_cmd[0], "pkexec")
        self.assertNotIn("pkexec", called_cmd)
        # It must be the systemctl stub
        self.assertIn("systemctl", called_cmd[0])

    def test_system_start_invokes_systemctl_directly(self):
        """System-scope mutations must invoke systemctl directly, not pkexec."""
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "")
            data, ec = _run_units("start", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 0)
            self.assertTrue(data["ok"])
            self._assert_invokes_systemctl_not_pkexec(mock_run, "system")

    def test_system_stop_invokes_systemctl_directly(self):
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "")
            data, ec = _run_units("stop", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 0)
            self._assert_invokes_systemctl_not_pkexec(mock_run, "system")

    def test_system_restart_invokes_systemctl_directly(self):
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "")
            data, ec = _run_units("restart", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 0)
            self._assert_invokes_systemctl_not_pkexec(mock_run, "system")

    def test_system_enable_invokes_systemctl_directly(self):
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "")
            data, ec = _run_units("enable", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 0)
            self._assert_invokes_systemctl_not_pkexec(mock_run, "system")

    def test_system_disable_invokes_systemctl_directly(self):
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "")
            data, ec = _run_units("disable", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 0)
            self._assert_invokes_systemctl_not_pkexec(mock_run, "system")

    def test_system_mask_invokes_systemctl_directly(self):
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "")
            data, ec = _run_units("mask", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 0)
            self._assert_invokes_systemctl_not_pkexec(mock_run, "system")

    def test_system_unmask_invokes_systemctl_directly(self):
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "")
            data, ec = _run_units("unmask", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 0)
            self._assert_invokes_systemctl_not_pkexec(mock_run, "system")

    def test_system_readonly_invokes_systemctl_directly(self):
        """System read-only (status) should also use systemctl directly."""
        data, ec = _run_units("status", "ssh.service", "--scope", "system")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])

    def test_user_enable_succeeds(self):
        data, ec = _run_units("enable", "nginx.service", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])


class TestDaemonReload(unittest.TestCase):
    def test_daemon_reload_system_invokes_systemctl_directly(self):
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "")
            data, ec = _run_units("daemon-reload", "--scope", "system")
            self.assertEqual(ec, 0)
            self.assertTrue(data["ok"])
            called_cmd = mock_run.call_args[0][0]
            self.assertNotIn("pkexec", called_cmd)
            self.assertIn("systemctl", called_cmd[0])

    def test_daemon_reload_user_succeeds(self):
        data, ec = _run_units("daemon-reload", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])


class TestErrorHandling(unittest.TestCase):
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
        self.assertIn("canElevate", d)
        self.assertIn("scopeUser", d)
        self.assertIn("scopeSystem", d)
        # systemctl should be found since our stub exists
        self.assertTrue(d["systemctl"])
        self.assertTrue(d["journalctl"])

    def test_diagnose_reports_polkit_agent_field(self):
        data, ec = _run_units("diagnose")
        self.assertEqual(ec, 0)
        d = data["data"]
        self.assertIn("polkitAgent", d)
        # polkitAgent should be a bool
        self.assertIsInstance(d["polkitAgent"], bool)

    def test_diagnose_canElevate_false_when_no_agent(self):
        """canElevate must be False when no polkit agent runs."""
        with unittest.mock.patch.object(units, "_polkit_agent_running", return_value=False):
            data, ec = _run_units("diagnose")
            self.assertEqual(ec, 0)
            d = data["data"]
            self.assertFalse(d["canElevate"])
            self.assertFalse(d["polkitAgent"])

    def test_diagnose_canElevate_true_when_agent_running(self):
        """canElevate must be True when a polkit agent is present."""
        with unittest.mock.patch.object(units, "_polkit_agent_running", return_value=True):
            data, ec = _run_units("diagnose")
            self.assertEqual(ec, 0)
            d = data["data"]
            self.assertTrue(d["canElevate"])
            self.assertTrue(d["polkitAgent"])

    def test_diagnose_no_pkexec_field(self):
        """pkexec is no longer part of the diagnose output."""
        data, ec = _run_units("diagnose")
        self.assertEqual(ec, 0)
        d = data["data"]
        self.assertNotIn("pkexec", d)


class TestTimeoutHandling(unittest.TestCase):
    """Tests that EXIT_TIMEOUT surfaces as a 'timeout' error code."""

    def test_mutate_timeout_returns_timeout_error(self):
        with unittest.mock.patch.object(units, "_run", return_value=(units.EXIT_TIMEOUT, "", "")):
            data, ec = _run_units("start", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 124)
            self.assertFalse(data["ok"])
            self.assertEqual(data["error"]["code"], "timeout")
            self.assertIn("polkit auth agent", data["error"]["message"])

    def test_daemon_reload_timeout_returns_timeout_error(self):
        with unittest.mock.patch.object(units, "_run", return_value=(units.EXIT_TIMEOUT, "", "")):
            data, ec = _run_units("daemon-reload", "--scope", "system")
            self.assertEqual(ec, 124)
            self.assertFalse(data["ok"])
            self.assertEqual(data["error"]["code"], "timeout")
            self.assertIn("polkit auth agent", data["error"]["message"])

    def test_run_checked_timeout_returns_timeout_error(self):
        with unittest.mock.patch.object(units, "_run", return_value=(units.EXIT_TIMEOUT, "", "")):
            data, ec = _run_units("status", "ssh.service", "--scope", "user")
            self.assertEqual(ec, 124)
            self.assertFalse(data["ok"])
            self.assertEqual(data["error"]["code"], "timeout")


class TestListUnitFiles(unittest.TestCase):
    def test_list_unit_files_system(self):
        data, ec = _run_units("list-unit-files", "--scope", "system")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        self.assertEqual(data["scope"], "system")
        units_list = data["data"]["units"]
        self.assertGreater(len(units_list), 0)

    def test_list_unit_files_user(self):
        data, ec = _run_units("list-unit-files", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        self.assertEqual(data["scope"], "user")
        units_list = data["data"]["units"]
        self.assertGreater(len(units_list), 0)

    def test_list_unit_files_parses_file_state_and_preset(self):
        data, ec = _run_units("list-unit-files", "--scope", "system")
        self.assertEqual(ec, 0)
        for item in data["data"]["units"]:
            self.assertIn("fileState", item)
            self.assertIn("preset", item)
            self.assertNotEqual(item["fileState"], "")
            self.assertNotEqual(item["preset"], "")

    def test_list_unit_files_type_filter(self):
        data, ec = _run_units("list-unit-files", "--scope", "system", "--types", "service")
        self.assertEqual(ec, 0)
        units_list = data["data"]["units"]
        for u in units_list:
            self.assertEqual(u["type"], "service")
        # fprintd is a service, should be present
        names = [u["name"] for u in units_list]
        self.assertIn("fprintd.service", names)
        # pipewire-pulse.socket should NOT be present (it's a socket)
        self.assertNotIn("pipewire-pulse.socket", names)

    def test_list_unit_files_state_filter(self):
        data, ec = _run_units("list-unit-files", "--scope", "system", "--states", "masked")
        self.assertEqual(ec, 0)
        units_list = data["data"]["units"]
        self.assertEqual(len(units_list), 1)
        self.assertEqual(units_list[0]["name"], "test-masked.service")
        self.assertEqual(units_list[0]["fileState"], "masked")

    def test_list_unit_files_missing_scope_returns_usage(self):
        data, ec = _run_units("list-unit-files")
        self.assertEqual(ec, 2)
        self.assertFalse(data["ok"])
        self.assertEqual(data["error"]["code"], "usage")


if __name__ == "__main__":
    unittest.main()
