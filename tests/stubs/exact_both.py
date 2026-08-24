#!/usr/bin/env python3
"""Stub that writes exactly N bytes to stdout and M bytes to stderr
simultaneously (via threads).

Usage: exact_both.py N M
"""
import os
import sys
import threading

n = int(sys.argv[1]) if len(sys.argv) > 1 else 0
m = int(sys.argv[2]) if len(sys.argv) > 2 else 0


def write_stdout():
    os.write(sys.stdout.fileno(), b"x" * n)


def write_stderr():
    os.write(sys.stderr.fileno(), b"y" * m)


threads = [threading.Thread(target=write_stdout),
           threading.Thread(target=write_stderr)]
for t in threads:
    t.start()
for t in threads:
    t.join()
