#!/usr/bin/env python3
"""Stub journalctl for unit tests. Replays canned output."""
import os
import sys

CANNED_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "canned")

args = sys.argv[1:]

canned_path = os.path.join(CANNED_DIR, "journal_sshd.txt")
if os.path.exists(canned_path):
    with open(canned_path) as f:
        print(f.read(), end="")

sys.exit(0)
