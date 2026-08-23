#!/usr/bin/env python3
"""Stub systemctl that succeeds on list-units but fails on list-unit-files."""
import os
import sys

CANNED_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "canned")

args = sys.argv[1:]
remaining = [a for a in args if a != "--user"]

if remaining and remaining[0] == "list-units":
    # Succeed with normal list output
    is_user = "--user" in args
    if is_user:
        canned = os.path.join(CANNED_DIR, "list_user.txt")
    else:
        canned = os.path.join(CANNED_DIR, "list_system.txt")
    if os.path.exists(canned):
        with open(canned) as f:
            print(f.read(), end="")
    sys.exit(0)
elif remaining and remaining[0] == "list-unit-files":
    # Fail
    print("list-unit-files not supported", file=sys.stderr)
    sys.exit(1)
else:
    # Succeed silently for mutations etc.
    sys.exit(0)
