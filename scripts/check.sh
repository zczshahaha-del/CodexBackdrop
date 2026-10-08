#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

node_binary="${NODE_BIN:-}"
if [[ -z "$node_binary" ]]; then
  codex_app_path="${CODEX_APP_PATH:-/Applications/ChatGPT.app}"
  if [[ -x "$codex_app_path/Contents/Resources/cua_node/bin/node" ]]; then
    node_binary="$codex_app_path/Contents/Resources/cua_node/bin/node"
  elif [[ -x /Applications/Codex.app/Contents/Resources/cua_node/bin/node ]]; then
    node_binary=/Applications/Codex.app/Contents/Resources/cua_node/bin/node
  else
    node_binary="$(command -v node || true)"
  fi
fi
if [[ -z "$node_binary" || ! -x "$node_binary" ]]; then
  echo "需要 Node.js 22+；可通过 NODE_BIN 指定可执行文件。" >&2
  exit 1
fi
"$node_binary" --input-type=module -e 'if (Number(process.versions.node.split(".")[0]) < 22) throw new Error("需要 Node.js 22+")'
for source_file in src/helper.mjs tests/*.mjs tools/*.mjs; do
  "$node_binary" --check "$source_file"
done
plutil -lint src/Info.plist
bash -n scripts/build.sh
bash -n scripts/check.sh
echo "脚本语法与应用信息检查通过。"
