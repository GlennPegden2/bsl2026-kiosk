#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "info" ]]; then
    # pi-gen checks for the word "rootless" and forces sudo; filter that marker.
    docker "$@" | grep -vi rootless
else
    docker "$@"
fi
