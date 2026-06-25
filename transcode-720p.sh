#!/bin/bash
# transcode-720p.sh: 通用视频转码工具
# 用法: transcode-720p.sh <input.mp4> [output.mp4]
# 行为: 短边缩到 720p，保留原始横纵比，h264_videotoolbox -b:v 1500k，音频 -c copy
# 失败: 保留 .partial 便于诊断，非 0 退出

set -euo pipefail

if [[ $# -lt 1 ]] || [[ $# -gt 2 ]]; then
  echo "usage: $0 <input.mp4> [output.mp4]" >&2
  exit 64
fi

INPUT="$1"

[[ -f "${INPUT}" ]] || { echo "❌ input not found: ${INPUT}" >&2; exit 66; }

if [[ $# -eq 2 ]]; then
  OUTPUT="$2"
else
  DIR="$(dirname "${INPUT}")"
  STEM="$(basename "${INPUT}" .mp4)"
  OUTPUT="${DIR}/${STEM}-720p.mp4"
fi

[[ -f "${OUTPUT}" ]] && { echo "⚠️  output already exists: ${OUTPUT}"; exit 0; }

PARTIAL="${OUTPUT}.partial"

# 读 input 宽高，决定横屏/竖屏缩放策略
read_w_h() {
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
    -of csv=s=x:p=0 "$1" 2>/dev/null | head -1
}

DIM=$(read_w_h "${INPUT}")
W="${DIM%x*}"
H="${DIM#*x}"

# 默认按横屏处理（scale=-2:720 会让短边为 720）
# 竖屏视频: scale=720:-2 让宽为 720，高按比例
# 用 max 函数让 "短边" 为 720
if [[ "${W}" -ge "${H}" ]]; then
  SCALE="-vf scale=-2:720"
else
  SCALE="-vf scale=720:-2"
fi

ffmpeg -y -loglevel warning \
  -i "${INPUT}" \
  ${SCALE} \
  -c:v h264_videotoolbox -b:v 1500k \
  -c:a copy \
  -f mp4 \
  "${PARTIAL}"

[[ -f "${PARTIAL}" ]] || { echo "❌ transcode failed: no partial output" >&2; exit 1; }

# atomic rename
mv "${PARTIAL}" "${OUTPUT}"
echo "[OK] ${OUTPUT} (${W}x${H} → 720p)"
