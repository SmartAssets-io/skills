#!/usr/bin/env bash
#
# git-push.sh - Canonical Smart Assets git push wrapper
#
# This is the canonical Pi/genre-namespaced entrypoint for the Smart Assets
# git push workflow. It delegates to agentic-git-commit-push.sh --push-only,
# which remains available as the legacy recursive-push implementation path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_AITOOLS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -x "$SCRIPT_DIR/agentic-git-commit-push.sh" ]]; then
	exec "$SCRIPT_DIR/agentic-git-commit-push.sh" --push-only "$@"
fi

exec "$PROJECT_AITOOLS_DIR/hooks/agentic-git-commit-push.sh" --push-only "$@"
