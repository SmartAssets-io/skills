#!/usr/bin/env bash
#
# git-commit.sh - Canonical Smart Assets git commit wrapper
#
# This is the canonical Pi/genre-namespaced entrypoint for the Smart Assets
# git commit workflow. It delegates to quick-commit.sh, which remains available
# as the legacy compatibility implementation and command alias.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/quick-commit.sh" "$@"
