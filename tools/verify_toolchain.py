#!/usr/bin/env python3
"""Enforce the project's documented minimum compiler version in CI."""
import re
import subprocess
import sys

def main():
    result = subprocess.run(["moon", "version", "--all"], capture_output=True, text=True)
    print(result.stdout, end="")
    if result.returncode:
        print(result.stderr, file=sys.stderr)
        return result.returncode
    match = re.search(r"(?m)^moonc\s+v?(\d+)\.(\d+)\.(\d+)", result.stdout)
    if not match or tuple(map(int, match.groups())) < (0, 10, 16):
        print("Required: moonc >= 0.10.16", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
