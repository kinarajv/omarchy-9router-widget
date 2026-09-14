#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v zig >/dev/null 2>&1; then
  echo "Error: zig is required to build fetch." >&2
  exit 1
fi

echo "Building fetch using Zig..."
zig build-exe -O ReleaseSmall fetch.zig
rm -f fetch.o
chmod +x fetch
echo "Build successful: ./fetch ($(stat -c%s fetch 2>/dev/null || stat -f%z fetch) bytes)"
