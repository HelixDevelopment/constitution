#!/usr/bin/env python3
"""Effective mode of a .workable-items-sync.yaml, decided by the SAME validator the engine uses (hooks must not grep YAML).
Prints one word: off | dry-run | apply | invalid. Exit 0 for off/dry-run/apply, 2 for invalid (an invalid declaration is never ON)."""
import sys

from . import config


def effective(path):
    cfg, errs = config.load(path)
    if errs:
        return "invalid", errs
    return ("off" if not cfg["enabled"] else cfg["mode"]), []


def main(argv):
    m, errs = effective(argv[0] if argv else ".workable-items-sync.yaml")
    print(m)
    return 2 if m == "invalid" else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
