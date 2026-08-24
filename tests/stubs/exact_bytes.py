#!/usr/bin/env python3
"""Stub that writes exactly N bytes to stdout or stderr.

Usage: exact_bytes.py N [stderr]

If the second argument is ``stderr`` the data goes to stderr;
otherwise it goes to stdout.
"""
import os
import sys

n = int(sys.argv[1]) if len(sys.argv) > 1 else 0
use_stderr = len(sys.argv) > 2 and sys.argv[2] == "stderr"
fd = sys.stderr.fileno() if use_stderr else sys.stdout.fileno()
os.write(fd, b"x" * n)
