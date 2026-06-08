#!/usr/bin/env bash
# Remove the installed cspot binary.
#   ./scripts/uninstall.sh            → removes ~/.local/bin/cspot
#   PREFIX=/usr/local/bin ./scripts/uninstall.sh
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local/bin}"
if [ -f "$PREFIX/cspot" ]; then
    rm -f "$PREFIX/cspot"
    echo "Removed: $PREFIX/cspot"
else
    echo "Nothing to remove at $PREFIX/cspot"
fi
