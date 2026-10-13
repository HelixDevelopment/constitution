# shellcheck shell=bash
# BASH_ENV shim: a ulimit that writes to stderr and fails (round-5b leak test).
ulimit() { echo LEAK >&2; return 1; }
