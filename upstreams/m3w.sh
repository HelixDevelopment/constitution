#!/bin/bash

export UPSTREAMABLE_REPOSITORY="ssh://git@git.m3w.org:2222/Helix/constitution.git"

# GitHub is the primary upstream: `origin` fetches from here, so this is
# the pull source of truth. Declared explicitly rather than left to the
# lexicographic fallback, which resolved to GitFlic and would silently
# repoint the moment an upstream sorting earlier was added (§11.4.111 —
# identity must never depend on position).
export UPSTREAMABLE_PRIMARY=0
