#!/usr/bin/env python3
"""osystemd CLI helper — JSON envelope over stdout.

Environment variables:
    OSYSTEMD_SYSTEMCTL   Path to systemctl (default: systemctl)
    OSYSTEMD_JOURNALCTL  Path to journalctl (default: journalctl)
    OSYSTEMD_PKEXEC      Path to pkexec (default: pkexec)
    OSYSTEMD_STATE_DIR   Reserved for future use
"""

import json
import os
import shutil
import subprocess
import sys

__version__ = "0.2.0"

DEFAULT_TYPES = [
    "service", "timer", "socket", "mount",
    "automount", "path", "swap", "target",
]

MUTATION_ACTIONS = frozenset({
    "start", "stop", "restart", "enable", "disable",
    "mask", "unmask", "daemon-reload",
})

# Sentinel exit codes returned from _run so callers can distinguish
# "command not found" from "command timed out" from "real non-zero exit".
EXIT_TIMEOUT = -2
EXIT_NOT_FOUND = -1


# ── helpers ──────────────────────────────────────────────────────────────

def _env(name, default):
    return os.environ.get(name, default)


def _ctl():
    return _env("OSYSTEMD_SYSTEMCTL", "systemctl")


def _jctl():
    return _env("OSYSTEMD_JOURNALCTL", "journalctl")


def _pkexec():
    return _env("OSYSTEMD_PKEXEC", "pkexec")


def _ok(scope, action, data):
    return json.dumps({"ok": True, "scope": scope, "action": action, "data": data})


def _err(scope, action, code, message, stderr=""):
    return json.dumps({
        "ok": False,
        "scope": scope,
        "action": action,
        "error": {"code": code, "message": message, "stderr": stderr},
    })


def _run(cmd):
    """Run a command, return (exitcode, stdout, stderr)."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired as exc:
        # Capture partial output so the panel can show what the command
        # produced before being killed (helpful when pkexec was hung waiting
        # for a polkit agent that never appeared).
        return EXIT_TIMEOUT, (
            exc.stdout.decode() if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        ), (
            exc.stderr.decode() if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        )
    except FileNotFoundError:
        return EXIT_NOT_FOUND, "", f"{cmd[0]}: not found"
    except Exception as exc:
        return EXIT_NOT_FOUND, "", str(exc)


def _run_checked(cmd, scope, action):
    """Run a command; produce JSON envelope on success or the appropriate error."""
    ec, out, err = _run(cmd)
    if ec == EXIT_TIMEOUT:
        msg = (
            f"{action} timed out after 30s — usually means pkexec is waiting for a "
            f"polkit auth agent that isn't running in this session. Install one "
            f"(e.g. polkit-gnome) and add an exec-once to start it at login."
        )
        return _err(scope, action, "timeout", msg, (err or "").strip()), 124
    if ec == EXIT_NOT_FOUND:
        return _err(scope, action, "binary_missing",
                     f"Binary not found: {cmd[0]}", err), 3
    if ec is None:  # defensive — should not happen now but preserve old behaviour
        return _err(scope, action, "binary_missing",
                     f"Binary not found: {cmd[0]}", err), 3
    if ec != 0:
        return _err(scope, action, "command_failed",
                     f"{cmd[0]} exited with code {ec}", err.strip()), 1
    return out, 0


def _needs_pkexec(scope, action):
    return scope == "system" and action in MUTATION_ACTIONS


# ── subcommands ──────────────────────────────────────────────────────────

def cmd_list(args, scope):
    type_filter = ",".join(DEFAULT_TYPES)
    state_filter = ""
    filter_str = ""

    i = 0
    while i < len(args):
        if args[i] == "--types" and i + 1 < len(args):
            type_filter = args[i + 1]
            i += 2
        elif args[i] == "--states" and i + 1 < len(args):
            state_filter = args[i + 1]
            i += 2
        elif args[i] == "--filter" and i + 1 < len(args):
            filter_str = args[i + 1]
            i += 2
        elif args[i].startswith("--types="):
            type_filter = args[i].split("=", 1)[1]
            i += 1
        elif args[i].startswith("--states="):
            state_filter = args[i].split("=", 1)[1]
            i += 1
        elif args[i].startswith("--filter="):
            filter_str = args[i].split("=", 1)[1]
            i += 1
        else:
            i += 1

    cmd = [_ctl(), "list-units", "--all", "--plain", "--no-legend"]
    if scope == "user":
        cmd.append("--user")
    if type_filter:
        cmd.append(f"--type={type_filter}")
    if state_filter:
        cmd.append(f"--state={state_filter}")

    ec, out, err = _run(cmd)
    if ec == EXIT_NOT_FOUND or ec is None:
        return _err(scope, "list", "binary_missing",
                     f"Binary not found: {_ctl()}", err), 3
    if ec == EXIT_TIMEOUT:
        return _err(scope, "list", "timeout",
                     f"list-units timed out after 30s", (err or "").strip()), 124
    if ec != 0:
        return _err(scope, "list", "command_failed",
                     f"list-units failed (exit {ec})", err.strip()), 1

    units = []
    for line in out.splitlines():
        line = line.rstrip()
        if not line:
            continue
        parts = line.split(None, 4)
        if len(parts) < 4:
            continue
        name = parts[0]
        load = parts[1]
        active = parts[2]
        sub = parts[3]
        desc = parts[4] if len(parts) > 4 else ""

        # derive type from name suffix
        dot = name.rfind(".")
        utype = name[dot + 1:] if dot >= 0 else ""

        # filter by search substring
        if filter_str:
            fl = filter_str.lower()
            if fl not in name.lower() and fl not in desc.lower():
                continue

        units.append({
            "name": name,
            "type": utype,
            "load": load,
            "active": active,
            "sub": sub,
            "description": desc,
        })

    return _ok(scope, "list", {"units": units}), 0


def cmd_status(args, scope):
    if not args:
        return _err(scope, "status", "usage", "Missing unit name", ""), 2
    unit = args[0]
    cmd = [_ctl(), "show", unit]
    if scope == "user":
        cmd.append("--user")

    out, ec = _run_checked(cmd, scope, "status")
    if ec != 0:
        return out, ec

    fields = {}
    wanted = {
        "LoadState", "ActiveState", "SubState", "Description",
        "MainPID", "FragmentPath", "UnitFileState", "UnitFilePreset",
        "ActiveEnterTimestamp",
    }
    for line in out.splitlines():
        if "=" in line:
            key, _, val = line.partition("=")
            if key in wanted:
                fields[key] = val if val else None

    return _ok(scope, "status", {"unit": unit, **fields}), 0


def cmd_show(args, scope):
    if not args:
        return _err(scope, "show", "usage", "Missing unit name", ""), 2
    unit = args[0]
    cmd = [_ctl(), "show", unit]
    if scope == "user":
        cmd.append("--user")

    out, ec = _run_checked(cmd, scope, "show")
    if ec != 0:
        return out, ec

    props = {}
    for line in out.splitlines():
        if "=" in line:
            key, _, val = line.partition("=")
            props[key] = val

    return _ok(scope, "show", {"unit": unit, "properties": props}), 0


def cmd_cat(args, scope):
    if not args:
        return _err(scope, "cat", "usage", "Missing unit name", ""), 2
    unit = args[0]
    cmd = [_ctl(), "cat", unit]
    if scope == "user":
        cmd.append("--user")

    out, ec = _run_checked(cmd, scope, "cat")
    if ec != 0:
        return out, ec

    raw = out
    files = []
    current = None
    for line in raw.splitlines():
        if line.startswith("# /"):
            if current is not None:
                current["content"] = current["content"].rstrip("\n")
            current = {"path": line[2:], "content": ""}
            files.append(current)
        elif current is not None:
            current["content"] += line + "\n"
    if current is not None:
        current["content"] = current["content"].rstrip("\n")

    return _ok(scope, "cat", {"unit": unit, "raw": raw, "files": files}), 0


def cmd_journal(args, scope):
    if not args:
        return _err(scope, "journal", "usage", "Missing unit name", ""), 2
    unit = args[0]
    lines_count = 100

    i = 1
    while i < len(args):
        if args[i] == "--lines" and i + 1 < len(args):
            try:
                lines_count = max(1, min(1000, int(args[i + 1])))
            except ValueError:
                lines_count = 100
            i += 2
        elif args[i].startswith("--lines="):
            try:
                lines_count = max(1, min(1000, int(args[i].split("=", 1)[1])))
            except ValueError:
                lines_count = 100
            i += 1
        else:
            i += 1

    cmd = [_jctl(), "--no-pager", "--output=cat", f"-n{lines_count}", "-u", unit]
    if scope == "user":
        cmd.append("--user")

    out, ec = _run_checked(cmd, scope, "journal")
    if ec != 0:
        return out, ec

    log_lines = [l for l in out.splitlines()]

    return _ok(scope, "journal", {"unit": unit, "lines": log_lines}), 0


def cmd_mutate(action, args, scope):
    if not args:
        return _err(scope, action, "usage", f"Missing unit name for {action}", ""), 2
    unit = args[0]
    cmd = []
    if _needs_pkexec(scope, action):
        cmd.append(_pkexec())
    cmd.extend([_ctl(), action, unit])
    if scope == "user":
        # insert --user after systemctl, before the action
        # cmd is now [pkexec,] systemctl action unit
        # insert --user before action
        idx = cmd.index(_ctl()) + 1 if _ctl() in cmd else 1
        cmd.insert(idx, "--user")

    ec, out, err = _run(cmd)
    if ec == EXIT_TIMEOUT:
        msg = (
            f"{action} timed out after 30s — usually means pkexec is waiting for "
            f"a polkit auth agent that isn't running in this session. Install "
            f"polkit-gnome and start it via Hyprland exec-once."
        )
        return _err(scope, action, "timeout", msg, (err or "").strip()), 124
    if ec == EXIT_NOT_FOUND or ec is None:
        return _err(scope, action, "binary_missing",
                     f"Binary not found: {cmd[0]}", err), 3
    if ec != 0:
        return _err(scope, action, "command_failed",
                     f"{action} {unit} failed (exit {ec})", (err or "").strip()), 1

    return _ok(scope, action, {"unit": unit}), 0


def cmd_daemon_reload(args, scope):
    cmd = []
    if _needs_pkexec(scope, "daemon-reload"):
        cmd.append(_pkexec())
    cmd.extend([_ctl(), "daemon-reload"])
    if scope == "user":
        idx = cmd.index(_ctl()) + 1 if _ctl() in cmd else 1
        cmd.insert(idx, "--user")

    ec, out, err = _run(cmd)
    if ec == EXIT_TIMEOUT:
        msg = (
            f"daemon-reload timed out after 30s — usually means pkexec is waiting "
            f"for a polkit auth agent that isn't running in this session. Install "
            f"polkit-gnome and start it via Hyprland exec-once."
        )
        return _err(scope, "daemon-reload", "timeout", msg, (err or "").strip()), 124
    if ec == EXIT_NOT_FOUND or ec is None:
        return _err(scope, "daemon-reload", "binary_missing",
                     f"Binary not found: {cmd[0]}", err), 3
    if ec != 0:
        return _err(scope, "daemon-reload", "command_failed",
                     f"daemon-reload failed (exit {ec})", (err or "").strip()), 1

    return _ok(scope, "daemon-reload", {}), 0


def cmd_diagnose():
    import platform
    pkexec_available = _bin_check(_pkexec())
    polkit_agent_ok = _polkit_agent_running()
    data = {
        "pythonVersion": platform.python_version(),
        "helperVersion": __version__,
        "systemctl":     _bin_check(_ctl()),
        "journalctl":    _bin_check(_jctl()),
        "pkexec":        pkexec_available,
        "polkitAgent":   polkit_agent_ok,
        "scopeUser":     True,
        "scopeSystem":   True,
        # canElevate is True only when both pkexec AND a polkit agent are
        # available. If pkexec exists but no agent is registered, canElevate
        # stays False so the UI doesn't lie — mutations will hang otherwise.
        "canElevate":    pkexec_available and polkit_agent_ok,
    }
    return _ok(None, "diagnose", data), 0


def _bin_check(path):
    return shutil.which(path) is not None


def _polkit_agent_running():
    """True if any polkit authentication agent is registered in this user's session.

    Polkit decides whether non-passwordless administrative actions succeed based
    on whether an agent is reachable. pgrep on the user's session catches the
    common agents shipped with Arch-based distros (polkit-gnome,
    polkit-kde-agent, polkit-mate, lxpolkit, etc.) without requiring us to
    introspect the session D-Bus from this helper process.
    """
    try:
        uid = os.getuid()
        # Match any "polkit" + "agent" — agent binaries all share that pair.
        r = subprocess.run(
            ["pgrep", "-u", str(uid), "-f", "polkit.*[Aa]uthentication.*[Aa]gent"],
            capture_output=True, text=True, timeout=2
        )
        return r.returncode == 0 and r.stdout.strip() != ""
    except Exception:
        # If pgrep isn't available or anything else goes wrong, fall back to the
        # historical behaviour (pkexec-on-PATH is sufficient) so we don't block
        # users on systems where pgrep isn't installed.
        return True


# ── argument parsing ─────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]
    if not args:
        print(_err(None, "", "usage", "Usage: units.py <command> [args]"), file=sys.stdout)
        sys.exit(2)

    cmd = args[0]

    if cmd == "diagnose":
        out, ec = cmd_diagnose()
        print(out)
        sys.exit(0)

    # scope is required for everything except diagnose
    scope = None
    remaining = []
    i = 1
    while i < len(args):
        if args[i] == "--scope" and i + 1 < len(args):
            scope = args[i + 1]
            i += 2
        elif args[i].startswith("--scope="):
            scope = args[i].split("=", 1)[1]
            i += 1
        else:
            remaining.append(args[i])
            i += 1

    if scope not in ("user", "system"):
        print(_err(None, cmd, "usage", "Missing or invalid --scope (user|system)"), file=sys.stdout)
        sys.exit(2)

    if cmd == "list":
        out, ec = cmd_list(remaining, scope)
    elif cmd == "status":
        out, ec = cmd_status(remaining, scope)
    elif cmd == "show":
        out, ec = cmd_show(remaining, scope)
    elif cmd == "cat":
        out, ec = cmd_cat(remaining, scope)
    elif cmd == "journal":
        out, ec = cmd_journal(remaining, scope)
    elif cmd == "daemon-reload":
        out, ec = cmd_daemon_reload(remaining, scope)
    elif cmd in MUTATION_ACTIONS:
        out, ec = cmd_mutate(cmd, remaining, scope)
    else:
        print(_err(scope, cmd, "usage", f"Unknown command: {cmd}"), file=sys.stdout)
        sys.exit(2)

    print(out)
    sys.exit(ec)


if __name__ == "__main__":
    main()
