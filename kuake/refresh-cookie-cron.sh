#!/usr/bin/env bash
# refresh-cookie-cron.sh: cron 定时刷新夸克 Cookie
#
# 由 crontab 每周一 10:00 调用，日志重定向到 logs/kuake-refresh.log
# 行为: 校验 → 失效则 headless 刷新 → 仍失败则记明确错误供人工介入

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

echo "[$(ts)] === kuake cookie 周期刷新 ==="

# 1) 校验
if bash "${SCRIPT_DIR}/check-quark-cookie.sh" 2>&1; then
  echo "[$(ts)] cookie 仍有效，无需刷新"
  exit 0
fi

# 2) 失效，headless 刷新
echo "[$(ts)] cookie 失效，尝试 headless 刷新..."
if python3 "${SCRIPT_DIR}/grab-quark-cookie.py" --headless 2>&1; then
  echo "[$(ts)] ✅ headless 刷新成功"
  exit 0
fi

# 3) headless 也失败（profile session 过期），需人工扫码
echo "[$(ts)] ❌ headless 刷新失败，需人工介入"
echo "  手动执行: python3 ${SCRIPT_DIR}/grab-quark-cookie.py"
exit 1
