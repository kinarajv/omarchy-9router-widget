#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if command -v zig >/dev/null 2>&1; then
  echo "Building fetch using Zig..."
  zig build-exe -O ReleaseSmall -lc fetch.zig
  chmod +x fetch
  echo "Build successful: ./fetch ($(stat -c%s fetch 2>/dev/null || stat -f%z fetch) bytes)"
else
  echo "Zig not found. Fallback to Python runner:"
  cp fetch.py fetch
  chmod +x fetch
  echo "Installed fetch runner (Python mode)."
fi
