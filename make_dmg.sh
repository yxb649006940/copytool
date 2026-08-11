#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
echo "make_dmg.sh 已合并到 create_dmg.sh，正在使用统一流程。"
"${SCRIPT_DIR}/create_dmg.sh"
