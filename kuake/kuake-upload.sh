#!/usr/bin/env bash
# kuake-upload.sh: 通用夸克网盘上传工具
#
# 用法: kuake-upload.sh <local_file> <quark_path>
#   quark_path 形如 /MyDrive/2024-01-01/xxx-720p.mp4
#
# 行为:
#   1) source ~/.kuake.env 获取 KUAKE_COOKIE（全局凭证，不随脚本目录走）
#   2) 校验 cookie + kuake CLI 存在
#   3) 从 quark_path 拆出最后一级目录，kuake create（祖先目录需已存在）
#   4) kuake upload 上传文件
#   5) 通过响应内容判定真实成功（kuake upload 即使失败也可能 exit 0）
#   6) 成功 exit 0，失败 exit 1；日志输出到 stderr
#
# 依赖: kuake CLI, ~/.kuake.env

set -uo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <local_file> <quark_path>" >&2
  exit 64
fi

LOCAL_FILE="$1"
QUARK_PATH="$2"

[[ -f "${LOCAL_FILE}" ]] || { echo "❌ local file not found: ${LOCAL_FILE}" >&2; exit 66; }

KUAKE_ENV="${HOME}/.kuake.env"
if [[ -f "${KUAKE_ENV}" ]]; then
  # shellcheck disable=SC1090
  source "${KUAKE_ENV}"
fi
[[ -n "${KUAKE_COOKIE:-}" ]] || { echo "❌ KUAKE_COOKIE 未设置（检查 ~/.kuake.env）" >&2; exit 78; }

command -v kuake >/dev/null || { echo "❌ kuake CLI 未找到" >&2; exit 78; }

# 拆分 quark_path: /MyDrive/2024-01-01/xxx.mp4
#   DIR_PART  = /MyDrive/2024-01-01
#   FILE_NAME = xxx.mp4
DIR_PART="$(dirname "${QUARK_PATH}")"

# 创建最后一级目录（祖先目录需已存在）
DIR_NAME="$(basename "${DIR_PART}")"
DIR_PARENT="$(dirname "${DIR_PART}")"
kuake create "${DIR_NAME}" "${DIR_PARENT}" >/dev/null 2>&1 || true

# 上传
UPLOAD_LOG="$(mktemp /tmp/kuake-upload-XXXX.log)"
trap 'rm -f "${UPLOAD_LOG}"' EXIT

kuake upload "${LOCAL_FILE}" "${QUARK_PATH}" > "${UPLOAD_LOG}" 2>&1 || true

# kuake upload 即使内部失败也可能 exit 0，必须通过响应内容判定真成功
if grep -qE '"success"\s*:\s*true|"code"\s*:\s*"OK"|"code"\s*:\s*"SKIPPED"' "${UPLOAD_LOG}"; then
  echo "✅ 上传成功: ${QUARK_PATH}" >&2
  exit 0
else
  echo "🔴 上传失败: ${QUARK_PATH}" >&2
  echo "  响应: $(tail -c 500 "${UPLOAD_LOG}")" >&2
  echo "  手动重试: source ~/.kuake.env && kuake upload '${LOCAL_FILE}' '${QUARK_PATH}'" >&2
  exit 1
fi
