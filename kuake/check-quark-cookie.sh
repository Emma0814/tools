#!/usr/bin/env bash
# check-quark-cookie.sh: 校验夸克 Cookie 有效性，失效可选自动刷新
# 用法: check-quark-cookie.sh [--auto-update]
#   无参数       仅校验
#   --auto-update 失效时调 grab-quark-cookie.py --headless 自动刷新
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUAKE="kuake"

[[ -f "$HOME/.kuake.env" ]] && source "$HOME/.kuake.env"
[[ -n "${KUAKE_COOKIE:-}" ]] || { echo "❌ KUAKE_COOKIE 未设置（检查 ~/.kuake.env）" >&2; exit 78; }

echo "==> 检查夸克 Cookie 状态..."
RESULT=$("$KUAKE" user 2>&1)

if echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('success') else 1)" 2>/dev/null; then
    NICK=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['nickname'])")
    MEMBER=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['member_type'])")
    echo "✅ Cookie 有效 | 账号: $NICK ($MEMBER)"
    exit 0
fi

echo "❌ Cookie 已失效"

if [[ "${1:-}" == "--auto-update" ]]; then
    echo "==> 通过 Playwright 自动刷新 Cookie..."
    python3 "$SCRIPT_DIR/grab-quark-cookie.py" --headless 2>&1
else
    echo ""
    echo "自动刷新: $0 --auto-update"
    echo "手动编辑: ~/.kuake.env"
fi
