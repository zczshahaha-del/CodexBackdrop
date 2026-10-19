#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p build
xcrun swiftc -module-cache-path build/module-cache-tests \
  tests/composer-surface/main.swift -o build/test-composer-surface
build/test-composer-surface "$project_root" "$@"
