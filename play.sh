#!/bin/sh
# Run a Grove game (default: the showcase).
cd "$(dirname "$0")"
exec ./bin/grove "${1:-games/demo}" "$@"
