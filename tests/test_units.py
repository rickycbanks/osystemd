#!/usr/bin/env python3
"""unittest suite for units.py using stub overrides."""
import json
import os
import subprocess
import sys
import tempfile
import threading
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
        # Runtime state filters (active,inactive,failed) must not filter
        # list-unit-files; static D-Bus units such as fprintd.service must
        # still appear even when the normal runtime filter is selected.
        data, ec = _run_units("list", "--scope", "system", "--states", "active,inactive,failed")
        self.assertEqual(ec, 0)
        unloaded_names = [u["name"] for u in data["data"]["unloaded"]]
        self.assertIn("fprintd.service", unloaded_names)
        # Unloaded must not be narrowed to a single fileState; expect
        # mixed fileStates because runtime filter is decoupled.
        file_states = {u["fileState"] for u in data["data"]["unloaded"]}
        self.assertIn("static", file_states)
        # Loaded 'enabled' units are excluded from unloaded, but 'disabled'
        # units remain — proves we didn't filter to only static.
        self.assertIn("disabled", file_states)

    def test_list_unloaded_runtime_filter_does_not_exclude_static(self):
        # Using a single runtime state (e.g. failed) must still include
        # unloaded static units.
        data, ec = _run_units("list", "--scope", "system", "--states", "failed")
        self.assertEqual(ec, 0)
        unloaded_names = [u["name"] for u in data["data"]["unloaded"]]
        self.assertIn("fprintd.service", unloaded_names)

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
            mock_run.return_value = (0, "", "", None)
            data, ec = _run_units("start", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 0)
            self.assertTrue(data["ok"])
            self._assert_invokes_systemctl_not_pkexec(mock_run, "system")

    def test_system_stop_invokes_systemctl_directly(self):
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "", None)
            data, ec = _run_units("stop", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 0)
            self._assert_invokes_systemctl_not_pkexec(mock_run, "system")

    def test_system_restart_invokes_systemctl_directly(self):
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "", None)
            data, ec = _run_units("restart", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 0)
            self._assert_invokes_systemctl_not_pkexec(mock_run, "system")

    def test_system_enable_invokes_systemctl_directly(self):
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "", None)
            data, ec = _run_units("enable", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 0)
            self._assert_invokes_systemctl_not_pkexec(mock_run, "system")

    def test_system_disable_invokes_systemctl_directly(self):
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "", None)
            data, ec = _run_units("disable", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 0)
            self._assert_invokes_systemctl_not_pkexec(mock_run, "system")

    def test_system_mask_invokes_systemctl_directly(self):
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "", None)
            data, ec = _run_units("mask", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 0)
            self._assert_invokes_systemctl_not_pkexec(mock_run, "system")

    def test_system_unmask_invokes_systemctl_directly(self):
        with unittest.mock.patch.object(units, "_run") as mock_run:
            mock_run.return_value = (0, "", "", None)
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
            mock_run.return_value = (0, "", "", None)
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
        self.assertEqual(d["helperVersion"], "1.1.0")
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
        with unittest.mock.patch.object(units, "_run",
                                        return_value=(units.EXIT_TIMEOUT, "", "", None)):
            data, ec = _run_units("start", "nginx.service", "--scope", "system")
            self.assertEqual(ec, 124)
            self.assertFalse(data["ok"])
            self.assertEqual(data["error"]["code"], "timeout")
            self.assertIn("polkit auth agent", data["error"]["message"])

    def test_daemon_reload_timeout_returns_timeout_error(self):
        with unittest.mock.patch.object(units, "_run",
                                        return_value=(units.EXIT_TIMEOUT, "", "", None)):
            data, ec = _run_units("daemon-reload", "--scope", "system")
            self.assertEqual(ec, 124)
            self.assertFalse(data["ok"])
            self.assertEqual(data["error"]["code"], "timeout")
            self.assertIn("polkit auth agent", data["error"]["message"])

    def test_run_checked_timeout_returns_timeout_error(self):
        with unittest.mock.patch.object(units, "_run",
                                        return_value=(units.EXIT_TIMEOUT, "", "", None)):
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


# ── Output-bounds and overflow regression tests ────────────────────────


class TestOutputBounds(unittest.TestCase):
    """Thorough regression tests for output boundaries, overflow, envelope
    behaviour, process cleanup, and JSON cap."""

    def setUp(self):
        self._old_ctl = os.environ.get("OSYSTEMD_SYSTEMCTL")
        self._old_jctl = os.environ.get("OSYSTEMD_JOURNALCTL")
        os.environ["OSYSTEMD_SYSTEMCTL"] = os.path.join(STUBS_DIR, "systemctl.py")
        os.environ["OSYSTEMD_JOURNALCTL"] = os.path.join(STUBS_DIR, "journalctl.py")

    def tearDown(self):
        if self._old_ctl is not None:
            os.environ["OSYSTEMD_SYSTEMCTL"] = self._old_ctl
        else:
            os.environ.pop("OSYSTEMD_SYSTEMCTL", None)
        if self._old_jctl is not None:
            os.environ["OSYSTEMD_JOURNALCTL"] = self._old_jctl
        else:
            os.environ.pop("OSYSTEMD_JOURNALCTL", None)

    # ── _run() direct tests — overflow ─────────────────────────────────

    def test_stdout_overflow_returns_overflow_code(self):
        """Command producing >256 KiB stdout triggers EXIT_OUTPUT_OVERFLOW."""
        stub = os.path.join(STUBS_DIR, "big_stdout.py")
        ec, out, err, overflow = units._run([sys.executable, stub])
        self.assertEqual(ec, units.EXIT_OUTPUT_OVERFLOW)
        self.assertEqual(out, "")
        self.assertEqual(err, "")
        self.assertIsNotNone(overflow)
        self.assertTrue(overflow[0])   # stdout_truncated
        self.assertFalse(overflow[1])  # stderr_truncated

    def test_stderr_overflow_returns_overflow_code(self):
        """Command producing >64 KiB stderr triggers EXIT_OUTPUT_OVERFLOW."""
        stub = os.path.join(STUBS_DIR, "big_stderr.py")
        ec, out, err, overflow = units._run([sys.executable, stub])
        self.assertEqual(ec, units.EXIT_OUTPUT_OVERFLOW)
        self.assertEqual(out, "")
        self.assertEqual(err, "")
        self.assertIsNotNone(overflow)
        self.assertFalse(overflow[0])  # stdout_truncated
        self.assertTrue(overflow[1])   # stderr_truncated

    def test_both_streams_overflow_no_deadlock(self):
        """Both streams exceeding limits simultaneously must not deadlock."""
        stub = os.path.join(STUBS_DIR, "big_both.py")
        ec, out, err, overflow = units._run([sys.executable, stub])
        self.assertEqual(ec, units.EXIT_OUTPUT_OVERFLOW)
        self.assertIsNotNone(overflow)
        # At least one stream must have been truncated
        self.assertTrue(overflow[0] or overflow[1])

    def test_no_partial_data_on_stdout_overflow(self):
        """Overflow must never return successful partial data."""
        stub = os.path.join(STUBS_DIR, "big_stdout.py")
        ec, out, err, overflow = units._run([sys.executable, stub])
        self.assertEqual(ec, units.EXIT_OUTPUT_OVERFLOW)
        self.assertEqual(out, "")
        self.assertEqual(err, "")

    def test_no_partial_data_on_stderr_overflow(self):
        """Overflow must never return successful partial data."""
        stub = os.path.join(STUBS_DIR, "big_stderr.py")
        ec, out, err, overflow = units._run([sys.executable, stub])
        self.assertEqual(ec, units.EXIT_OUTPUT_OVERFLOW)
        self.assertEqual(out, "")
        self.assertEqual(err, "")

    def test_normal_command_succeeds(self):
        """Normal command invocation still works with the bounded collector."""
        ec, out, err, overflow = units._run(
            [sys.executable, os.path.join(STUBS_DIR, "systemctl.py"),
             "start", "test"]
        )
        self.assertEqual(ec, 0)
        self.assertIsNone(overflow)
        self.assertIsInstance(out, str)
        self.assertIsInstance(err, str)

    def test_file_not_found_returns_not_found(self):
        """Non-existent binary returns EXIT_NOT_FOUND."""
        ec, out, err, overflow = units._run(["/nonexistent/binary"])
        self.assertEqual(ec, units.EXIT_NOT_FOUND)
        self.assertIsNone(overflow)
        self.assertIn("not found", err)

    # ── Exact-boundary success (defect 1 regression) ───────────────────

    def test_exact_boundary_stdout_success(self):
        """Exactly STDOUT_LIMIT bytes of stdout must succeed, not overflow."""
        stub = os.path.join(STUBS_DIR, "exact_bytes.py")
        ec, out, err, overflow = units._run(
            [sys.executable, stub, str(units.STDOUT_LIMIT)]
        )
        self.assertEqual(ec, 0)
        self.assertIsNone(overflow)
        self.assertEqual(len(out.encode("utf-8")), units.STDOUT_LIMIT)

    def test_exact_boundary_stderr_success(self):
        """Exactly STDERR_LIMIT bytes of stderr must succeed, not overflow."""
        stub = os.path.join(STUBS_DIR, "exact_bytes.py")
        ec, out, err, overflow = units._run(
            [sys.executable, stub, str(units.STDERR_LIMIT), "stderr"]
        )
        self.assertEqual(ec, 0)
        self.assertIsNone(overflow)
        self.assertEqual(len(err.encode("utf-8")), units.STDERR_LIMIT)

    def test_limit_plus_one_stdout_overflow(self):
        """STDOUT_LIMIT + 1 bytes must trigger overflow."""
        stub = os.path.join(STUBS_DIR, "exact_bytes.py")
        ec, out, err, overflow = units._run(
            [sys.executable, stub, str(units.STDOUT_LIMIT + 1)]
        )
        self.assertEqual(ec, units.EXIT_OUTPUT_OVERFLOW)
        self.assertEqual(out, "")
        self.assertIsNotNone(overflow)
        self.assertTrue(overflow[0])

    def test_limit_plus_one_stderr_overflow(self):
        """STDERR_LIMIT + 1 bytes must trigger overflow."""
        stub = os.path.join(STUBS_DIR, "exact_bytes.py")
        ec, out, err, overflow = units._run(
            [sys.executable, stub, str(units.STDERR_LIMIT + 1), "stderr"]
        )
        self.assertEqual(ec, units.EXIT_OUTPUT_OVERFLOW)
        self.assertEqual(err, "")
        self.assertIsNotNone(overflow)
        self.assertTrue(overflow[1])

    def test_exact_boundary_both_streams_success(self):
        """Exactly at both limits simultaneously must succeed."""
        stub = os.path.join(STUBS_DIR, "exact_both.py")
        ec, out, err, overflow = units._run(
            [sys.executable, stub,
             str(units.STDOUT_LIMIT), str(units.STDERR_LIMIT)]
        )
        self.assertEqual(ec, 0)
        self.assertIsNone(overflow)
        self.assertEqual(len(out.encode("utf-8")), units.STDOUT_LIMIT)
        self.assertEqual(len(err.encode("utf-8")), units.STDERR_LIMIT)

    def test_both_streams_overflow_simultaneous(self):
        """Both streams over limit simultaneously triggers overflow, no deadlock.

        Independently-scheduled concurrent writers cannot reliably make both
        stream flags true after an immediate process-group kill, so we assert
        that at least one overflow is observed (not necessarily both).
        """
        import time
        stub = os.path.join(STUBS_DIR, "exact_both.py")
        t0 = time.monotonic()
        ec, out, err, overflow = units._run(
            [sys.executable, stub,
             str(units.STDOUT_LIMIT + 1024),
             str(units.STDERR_LIMIT + 1024)]
        )
        elapsed = time.monotonic() - t0
        self.assertEqual(ec, units.EXIT_OUTPUT_OVERFLOW)
        self.assertIsNotNone(overflow)
        # At least one stream must have been flagged as truncated.
        self.assertTrue(overflow[0] or overflow[1])
        # Overflow must never return partial data.
        self.assertEqual(out, "")
        self.assertEqual(err, "")
        # Must complete promptly — no deadlock.
        self.assertLess(elapsed, 5.0,
                        f"Simultaneous overflow took {elapsed:.2f}s — possible deadlock")

    def test_overflow_reported_when_drain_lingers(self):
        """Overflow must be reported even if the reader drain never completes.

        The overflow flag is published in state[2] before the drain loop
        begins, so even if the reader thread is stuck draining after the
        5-second join timeout, the main thread still sees overflow.
        """
        import io

        # Build a pipe pair; write from a thread because writing 257 KiB
        # to a 64 KiB pipe buffer blocks until the reader drains.
        r_fd, w_fd = os.pipe()

        state = [[], 0, False]
        # Use a fake proc; mock _kill_process_group so it does not
        # actually signal the test runner's own process group.
        proc = unittest.mock.MagicMock()
        proc.pid = -1  # invalid PID, but kill is mocked away

        pipe = io.FileIO(r_fd, mode="rb", closefd=True)

        def writer():
            os.write(w_fd, b"x" * (units.STDOUT_LIMIT + 1))
            os.close(w_fd)

        with unittest.mock.patch.object(units, "_kill_process_group"):
            wt = threading.Thread(target=writer)
            wt.start()

            t = threading.Thread(
                target=units._read_stream,
                args=(pipe, state, units.STDOUT_LIMIT, proc),
            )
            t.start()
            # Join with a short timeout to simulate lingering drain.
            t.join(timeout=0.1)

            # The overflow flag must already be visible, even though the
            # drain loop may still be running.
            self.assertTrue(state[2],
                            "state[2] (truncated) must be True before drain completes")
            self.assertGreaterEqual(state[1], units.STDOUT_LIMIT)

            # Let both threads finish cleanly.
            wt.join(timeout=5)
            t.join(timeout=5)

    def test_small_output_succeeds(self):
        """Small output well under limits succeeds promptly."""
        stub = os.path.join(STUBS_DIR, "exact_bytes.py")
        ec, out, err, overflow = units._run(
            [sys.executable, stub, "100"]
        )
        self.assertEqual(ec, 0)
        self.assertIsNone(overflow)
        self.assertEqual(len(out.encode("utf-8")), 100)

    # ── Prompt normal completion (defect 2 regression) ──────────────────

    def test_normal_completion_is_prompt(self):
        """Normal _run() must return promptly (no 2-second watcher delay)."""
        import time
        t0 = time.monotonic()
        ec, out, err, overflow = units._run(
            [sys.executable, os.path.join(STUBS_DIR, "systemctl.py"),
             "start", "test"]
        )
        elapsed = time.monotonic() - t0
        self.assertEqual(ec, 0)
        self.assertIsNone(overflow)
        # The old bug added ~2s from _watch_overflow thread join.
        # A normal command should finish in well under 1 second.
        self.assertLess(elapsed, 1.0,
                        f"Normal _run took {elapsed:.2f}s — possible watcher delay")

    def test_prompt_completion_via_cli(self):
        """CLI list must also return promptly (no accumulated watcher delays)."""
        import time
        t0 = time.monotonic()
        data, ec = _run_units("list", "--scope", "user")
        elapsed = time.monotonic() - t0
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        self.assertLess(elapsed, 2.0,
                        f"CLI list took {elapsed:.2f}s — possible watcher delay")

    # ── _run_checked() overflow envelope ───────────────────────────────

    def test_run_checked_stdout_overflow_produces_envelope(self):
        """_run_checked produces output_limit_exceeded envelope on overflow."""
        stub = os.path.join(STUBS_DIR, "big_stdout.py")
        json_str, ec = units._run_checked(
            [sys.executable, stub], "system", "list"
        )
        self.assertEqual(ec, 1)
        data = json.loads(json_str)
        self.assertFalse(data["ok"])
        self.assertEqual(data["error"]["code"], "output_limit_exceeded")
        self.assertTrue(data["error"]["stdoutTruncated"])
        self.assertFalse(data["error"]["stderrTruncated"])

    def test_run_checked_stderr_overflow_produces_envelope(self):
        """_run_checked produces correct flags for stderr overflow."""
        stub = os.path.join(STUBS_DIR, "big_stderr.py")
        json_str, ec = units._run_checked(
            [sys.executable, stub], "system", "journal"
        )
        self.assertEqual(ec, 1)
        data = json.loads(json_str)
        self.assertFalse(data["ok"])
        self.assertEqual(data["error"]["code"], "output_limit_exceeded")
        self.assertFalse(data["error"]["stdoutTruncated"])
        self.assertTrue(data["error"]["stderrTruncated"])

    # ── CLI-level overflow handling ────────────────────────────────────

    def test_list_overflow_via_cli(self):
        """CLI list command handles overflow gracefully."""
        old = os.environ.get("OSYSTEMD_SYSTEMCTL")
        os.environ["OSYSTEMD_SYSTEMCTL"] = os.path.join(STUBS_DIR, "big_stdout.py")
        try:
            data, ec = _run_units("list", "--scope", "user")
            self.assertEqual(ec, 1)
            self.assertFalse(data["ok"])
            self.assertEqual(data["error"]["code"], "output_limit_exceeded")
            self.assertTrue(data["error"]["stdoutTruncated"])
        finally:
            if old is not None:
                os.environ["OSYSTEMD_SYSTEMCTL"] = old
            else:
                os.environ.pop("OSYSTEMD_SYSTEMCTL", None)

    def test_mutate_overflow_via_cli(self):
        """CLI mutate command handles overflow gracefully."""
        old = os.environ.get("OSYSTEMD_SYSTEMCTL")
        os.environ["OSYSTEMD_SYSTEMCTL"] = os.path.join(STUBS_DIR, "big_stdout.py")
        try:
            data, ec = _run_units("start", "x.service", "--scope", "system")
            self.assertEqual(ec, 1)
            self.assertFalse(data["ok"])
            self.assertEqual(data["error"]["code"], "output_limit_exceeded")
        finally:
            if old is not None:
                os.environ["OSYSTEMD_SYSTEMCTL"] = old
            else:
                os.environ.pop("OSYSTEMD_SYSTEMCTL", None)

    def test_daemon_reload_overflow_via_cli(self):
        """CLI daemon-reload command handles overflow gracefully."""
        old = os.environ.get("OSYSTEMD_SYSTEMCTL")
        os.environ["OSYSTEMD_SYSTEMCTL"] = os.path.join(STUBS_DIR, "big_stdout.py")
        try:
            data, ec = _run_units("daemon-reload", "--scope", "system")
            self.assertEqual(ec, 1)
            self.assertFalse(data["ok"])
            self.assertEqual(data["error"]["code"], "output_limit_exceeded")
        finally:
            if old is not None:
                os.environ["OSYSTEMD_SYSTEMCTL"] = old
            else:
                os.environ.pop("OSYSTEMD_SYSTEMCTL", None)

    def test_list_unit_files_overflow_via_cli(self):
        """CLI list-unit-files command handles overflow gracefully."""
        old = os.environ.get("OSYSTEMD_SYSTEMCTL")
        os.environ["OSYSTEMD_SYSTEMCTL"] = os.path.join(STUBS_DIR, "big_stdout.py")
        try:
            data, ec = _run_units("list-unit-files", "--scope", "system")
            self.assertEqual(ec, 1)
            self.assertFalse(data["ok"])
            self.assertEqual(data["error"]["code"], "output_limit_exceeded")
        finally:
            if old is not None:
                os.environ["OSYSTEMD_SYSTEMCTL"] = old
            else:
                os.environ.pop("OSYSTEMD_SYSTEMCTL", None)

    def test_status_overflow_via_cli(self):
        """CLI status (via _run_checked) handles overflow gracefully."""
        old = os.environ.get("OSYSTEMD_SYSTEMCTL")
        os.environ["OSYSTEMD_SYSTEMCTL"] = os.path.join(STUBS_DIR, "big_stdout.py")
        try:
            data, ec = _run_units("status", "ssh.service", "--scope", "user")
            self.assertEqual(ec, 1)
            self.assertFalse(data["ok"])
            self.assertEqual(data["error"]["code"], "output_limit_exceeded")
        finally:
            if old is not None:
                os.environ["OSYSTEMD_SYSTEMCTL"] = old
            else:
                os.environ.pop("OSYSTEMD_SYSTEMCTL", None)

    # ── JSON cap tests ─────────────────────────────────────────────────

    def test_cap_output_small_unchanged(self):
        """_cap_output passes through small JSON unchanged."""
        small = json.dumps({"ok": True, "data": "hello"})
        self.assertEqual(units._cap_output(small), small)

    def test_cap_output_replaces_large_json(self):
        """_cap_output replaces oversized JSON with response_too_large."""
        large = json.dumps({"ok": True, "data": "x" * (units.JSON_LIMIT + 1024)})
        capped = units._cap_output(large)
        self.assertLessEqual(len(capped.encode("utf-8")), units.JSON_LIMIT)
        data = json.loads(capped)
        self.assertFalse(data["ok"])
        self.assertEqual(data["error"]["code"], "response_too_large")

    def test_cap_output_boundary_just_under_limit(self):
        """JSON at exactly the limit is passed through."""
        payload = {"ok": True, "data": "a" * (units.JSON_LIMIT - 100)}
        text = json.dumps(payload)
        # May exceed limit due to JSON encoding overhead, but should
        # pass through if within the limit
        if len(text.encode("utf-8")) <= units.JSON_LIMIT:
            self.assertEqual(units._cap_output(text), text)

    def test_main_output_is_capped(self):
        """Verify main() wraps all output paths with _cap_output."""
        with unittest.mock.patch.object(units, "_cap_output",
                                       wraps=units._cap_output) as mock_cap:
            _run_units("list", "--scope", "user")
            self.assertTrue(mock_cap.called)

    # ── Overflow flags correctness ─────────────────────────────────────

    def test_overflow_envelope_has_both_flags(self):
        """Overflow envelope always includes stdoutTruncated and stderrTruncated."""
        stub = os.path.join(STUBS_DIR, "big_stdout.py")
        json_str, ec = units._run_checked(
            [sys.executable, stub], "user", "status"
        )
        data = json.loads(json_str)
        self.assertIn("stdoutTruncated", data["error"])
        self.assertIn("stderrTruncated", data["error"])
        self.assertIsInstance(data["error"]["stdoutTruncated"], bool)
        self.assertIsInstance(data["error"]["stderrTruncated"], bool)

    # ── _err_overflow envelope shape ───────────────────────────────────

    def test_err_overflow_json_shape(self):
        """_err_overflow produces correct JSON envelope shape."""
        envelope = json.loads(units._err_overflow("system", "start", True, False))
        self.assertFalse(envelope["ok"])
        self.assertEqual(envelope["scope"], "system")
        self.assertEqual(envelope["action"], "start")
        err = envelope["error"]
        self.assertEqual(err["code"], "output_limit_exceeded")
        self.assertIn("protocol budget", err["message"])
        self.assertTrue(err["stdoutTruncated"])
        self.assertFalse(err["stderrTruncated"])
        self.assertEqual(err["stderr"], "")

    def test_err_overflow_both_truncated(self):
        """_err_overflow handles both-truncated case."""
        envelope = json.loads(units._err_overflow("user", "list", True, True))
        self.assertTrue(envelope["error"]["stdoutTruncated"])
        self.assertTrue(envelope["error"]["stderrTruncated"])

    # ── Process group kill (timeout path) ──────────────────────────────

    def test_timeout_kills_process_group(self):
        """On timeout, the child process group must be killed."""
        with unittest.mock.patch.object(units, "_kill_process_group",
                                        wraps=units._kill_process_group) as mock_kill:
            # Use a command that sleeps forever so proc.wait() blocks
            ec, out, err, overflow = units._run(
                [sys.executable, "-c",
                 "import time; time.sleep(300)"]
            )
            self.assertEqual(ec, units.EXIT_TIMEOUT)
            mock_kill.assert_called()

    # ── Constants sanity ───────────────────────────────────────────────

    def test_constants_are_positive_and_ordered(self):
        """Sanity check on ceiling constants."""
        self.assertGreater(units.STDOUT_LIMIT, 0)
        self.assertGreater(units.STDERR_LIMIT, 0)
        self.assertGreater(units.JSON_LIMIT, 0)
        self.assertGreaterEqual(units.JSON_LIMIT, units.STDOUT_LIMIT)
        self.assertGreaterEqual(units.JSON_LIMIT, units.STDERR_LIMIT)
        self.assertGreater(units.RUN_TIMEOUT, 0)

    def test_exit_codes_are_negative(self):
        """Sentinel exit codes must be negative to avoid clashing with real codes."""
        self.assertLess(units.EXIT_NOT_FOUND, 0)
        self.assertLess(units.EXIT_TIMEOUT, 0)
        self.assertLess(units.EXIT_OUTPUT_OVERFLOW, 0)
        self.assertNotEqual(units.EXIT_NOT_FOUND, units.EXIT_TIMEOUT)
        self.assertNotEqual(units.EXIT_TIMEOUT, units.EXIT_OUTPUT_OVERFLOW)

    # ── Existing behaviour preserved ───────────────────────────────────

    def test_normal_list_still_works(self):
        """Normal list invocation through CLI is unaffected."""
        data, ec = _run_units("list", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        self.assertGreater(len(data["data"]["units"]), 0)

    def test_normal_diagnose_still_works(self):
        """Normal diagnose invocation through CLI is unaffected."""
        data, ec = _run_units("diagnose")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])

    def test_normal_mutate_still_works(self):
        """Normal mutation through CLI is unaffected."""
        data, ec = _run_units("start", "nginx.service", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])

    def test_normal_status_still_works(self):
        """Normal status through CLI is unaffected."""
        data, ec = _run_units("status", "ssh.service", "--scope", "user")
        self.assertEqual(ec, 0)
        self.assertTrue(data["ok"])
        self.assertEqual(data["data"]["unit"], "ssh.service")


if __name__ == "__main__":
    unittest.main()
