#!/usr/bin/env python3
"""Stub that produces oversized stdout for overflow testing."""
import os
import sys

# Write STDOUT_LIMIT + 1 KiB to stdout (bypass Python buffering)
data = b"x" * (256 * 1024 + 1024)
os.write(sys.stdout.fileno(), data)
