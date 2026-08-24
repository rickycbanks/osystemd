#!/usr/bin/env python3
"""Stub that produces oversized output on both streams simultaneously.

Writes to stdout and stderr in parallel threads so the bounded collector
must handle both streams without deadlock.
"""
import os
import sys
import threading


def write_stdout():
    # STDOUT_LIMIT + 1 KiB
    data = b"x" * (256 * 1024 + 1024)
    os.write(sys.stdout.fileno(), data)


def write_stderr():
    # STDERR_LIMIT + 1 KiB
    data = b"y" * (64 * 1024 + 1024)
    os.write(sys.stderr.fileno(), data)


threads = [threading.Thread(target=write_stdout),
           threading.Thread(target=write_stderr)]
for t in threads:
    t.start()
for t in threads:
    t.join()
