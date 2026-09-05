#!/usr/bin/env bash
# run.sh — run the agsh-stdlib suite tests (bats) for one component or all.
#
# Usage: bash agsh-stdlib/test/run.sh [name.bats ...]
#        (no argument = every *.bats in this directory)
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if (( $# )); then
  targets=("$@")
else
  targets=("$dir")
fi
exec bats "${targets[@]}"
