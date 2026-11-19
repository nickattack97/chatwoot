#!/usr/bin/env bash
# Removes whatever a CI check job left behind (containers and networks carrying its run label). Safe to run twice.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cleanup_run
