#!/usr/bin/env python3
"""Stub pkexec for unit tests.
Writes received argv to a temp file the test can read back."""
import os
import sys
import tempfile

tmp_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "canned")
os.makedirs(tmp_dir, exist_ok=True)

record_path = os.path.join(tmp_dir, ".pkexec_invocation.txt")
with open(record_path, "w") as f:
    f.write(" ".join(sys.argv))

sys.exit(0)
