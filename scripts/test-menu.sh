#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p build
xcrun swiftc -module-cache-path build/module-cache-tests \
  src/MenuInteraction.swift tests/menu-controls/main.swift -o build/test-menu-controls
build/test-menu-controls
