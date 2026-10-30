#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

if ! command -v go >/dev/null 2>&1; then
  printf 'Error: el panel requiere Go 1.24.2 o posterior.\n' >&2
  exit 1
fi

case "${1:-}" in
  --list)
    shift
    set -- list "$@"
    ;;
  --preview)
    shift
    set -- preview "$@"
    ;;
esac

cd -- "$PROJECT_DIR"
exec go run ./cmd/script-panel --project-dir "$PROJECT_DIR" "$@"
