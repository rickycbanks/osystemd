#!/usr/bin/env python3
"""Stub that produces oversized stderr for overflow testing."""
import os
import sys

# Write STDERR_LIMIT + 1 KiB to stderr (bypass Python buffering)
data = b"y" * (64 * 1024 + 1024)
os.write(sys.stderr.fileno(), data)
