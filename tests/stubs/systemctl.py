#!/usr/bin/env python3
"""Stub systemctl for unit tests. Replays canned output."""
import os
import sys

CANNED_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "canned")

args = sys.argv[1:]

# Check for --user flag
is_user = "--user" in args
remaining = [a for a in args if a != "--user"]

# Parse --type and --state flags for filtering
type_filter = None
state_filter = None
for a in remaining:
    if a.startswith("--type="):
        type_filter = set(a.split("=", 1)[1].split(","))
    elif a.startswith("--state="):
        state_filter = set(a.split("=", 1)[1].split(","))

# Determine the canned file
def pick_canned():
    if "--help" in remaining or "-h" in remaining:
        print("systemctl stub", file=sys.stderr)
        sys.exit(0)

    # list-units command
    if remaining and remaining[0] == "list-units":
        if is_user:
            return os.path.join(CANNED_DIR, "list_user.txt")
        return os.path.join(CANNED_DIR, "list_system.txt")

    # show command
    if remaining and remaining[0] == "show":
        return os.path.join(CANNED_DIR, "show_sshd.txt")

    # cat command
    if remaining and remaining[0] == "cat":
        return os.path.join(CANNED_DIR, "cat_sshd.txt")

    # For mutation commands (start, stop, restart, enable, disable, mask, unmask, daemon-reload)
    # just succeed silently
    return None

canned = pick_canned()
if canned and os.path.exists(canned):
    with open(canned) as f:
        lines = f.readlines()
    # Apply --type and --state filters (skip header line)
    if type_filter or state_filter:
        filtered = []
        for line in lines:
            parts = line.split(None, 4)
            if len(parts) < 4:
                continue  # skip header / empty lines
            name = parts[0]
            if name == "UNIT":
                continue  # skip header
            active = parts[2]
            dot = name.rfind(".")
            utype = name[dot + 1:] if dot >= 0 else ""
            if type_filter and utype not in type_filter:
                continue
            if state_filter and active not in state_filter:
                continue
            filtered.append(line)
        print("".join(filtered), end="")
    else:
        print("".join(lines), end="")
    sys.exit(0)

# For unknown or mutation commands, succeed silently
sys.exit(0)
