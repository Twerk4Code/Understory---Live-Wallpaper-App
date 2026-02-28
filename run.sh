#!/bin/zsh
# Understory — build and launch helper

set -e
SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

echo "🔨 Building Understory..."
swift build -c release 2>&1

BINARY=".build/release/Understory"

if [[ ! -f "$BINARY" ]]; then
  echo "❌ Build failed — binary not found at $BINARY"
  exit 1
fi

echo "✅ Build succeeded."
echo "🚀 Launching Understory..."
"$BINARY"
