#!/usr/bin/env bash
# Build cspot in release mode and install it onto your PATH (no Homebrew needed).
#   ./scripts/install.sh            → installs to ~/.local/bin
#   PREFIX=/usr/local/bin ./scripts/install.sh
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local/bin}"
cd "$(dirname "$0")/.."

echo "Building cspot (release)…"
swift build -c release

mkdir -p "$PREFIX"
install -m 0755 .build/release/cspot "$PREFIX/cspot"
echo "Installed: $PREFIX/cspot"

case ":$PATH:" in
    *":$PREFIX:"*) echo "✓ $PREFIX is on your PATH — try:  cspot \"report\"" ;;
    *) echo "⚠ $PREFIX is NOT on your PATH. Add it:"
       echo "    echo 'export PATH=\"$PREFIX:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" ;;
esac
