#!/bin/bash
set -uo pipefail

# 公共视频转码工具：保留原始比例，短边缩到 720
# 支持横屏（1280×720）和竖屏（720×1280），自动识别
#
# 用法：
#   tools/transcode-720p.sh <input.mp4> [output.mp4]
#   tools/transcode-720p.sh ~/Videos/锅师小课/xxx.mp4
#   tools/transcode-720p.sh ~/Videos/锅师小课/xxx.mp4 ~/Videos/锅师小课-720p/xxx_720p.mp4
#
# 输出：
#   - 不指定输出：同目录 <stem>-720p.mp4
#   - 指定输出：按指定路径
#
# 依赖：
#   - ffmpeg（brew install ffmpeg）
#   - Apple Silicon Mac（h264_videotoolbox 硬件加速）

if [[ $# -lt 1 ]]; then
  echo "用法: $0 <input.mp4> [output.mp4]" >&2
  exit 64
fi

IN="$1"
[[ -f "$IN" ]] || { echo "❌ 找不到文件: $IN" >&2; exit 66; }

DIR="$(dirname "$IN")"
STEM="$(basename "$IN" .mp4)"
EXT="${IN##*.}"

if [[ $# -ge 2 ]]; then
  OUT="$2"
else
  OUT="${DIR}/${STEM}-720p.${EXT}"
fi

PARTIAL="${OUT}.partial"

[[ -f "$OUT" ]] && { echo "⚠️  目标已存在: $OUT  跳过" >&2; exit 0; }

echo "=== 输入 ==="
ffprobe -v error -show_entries stream=width,height,bit_rate \
  -show_entries format=duration,size,bit_rate \
  -of default "$IN"

# 自动检测横屏 / 竖屏，短边缩到 720（保留原始比例）
W=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$IN")
H=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$IN")
if (( W >= H )); then
  SCALE_FILTER="scale=-2:720"
  echo "横屏 (${W}×${H}) → 输出 *×720（高 720，宽自动按比例）"
else
  SCALE_FILTER="scale=720:-2"
  echo "竖屏 (${W}×${H}) → 输出 720×*（宽 720，高自动按比例）"
fi

echo ""
echo "=== 转码 → $OUT ==="
START=$(date +%s)
ffmpeg -y -hide_banner -loglevel warning -stats \
  -i "$IN" \
  -vf "$SCALE_FILTER" \
  -c:v h264_videotoolbox -b:v 1500k \
  -c:a copy \
  -movflags +faststart \
  -f mp4 "$PARTIAL"

mv "$PARTIAL" "$OUT"
END=$(date +%s)

echo ""
echo "=== 输出 ==="
ffprobe -v error -show_entries stream=width,height,bit_rate \
  -show_entries format=duration,size,bit_rate \
  -of default "$OUT"

IN_SIZE=$(stat -f %z "$IN")
OUT_SIZE=$(stat -f %z "$OUT")
RATIO=$(echo "scale=1; (1 - $OUT_SIZE / $IN_SIZE) * 100" | bc)

IN_GB=$(echo "scale=2; $IN_SIZE/1024/1024/1024" | bc)
OUT_GB=$(echo "scale=2; $OUT_SIZE/1024/1024/1024" | bc)
ELAPSED_MIN=$(echo "scale=1; ($END-$START)/60" | bc)

echo ""
echo "✅ 转码完成: $((END-START))s"
echo "   原始: ${IN_GB} GB"
echo "   720p: ${OUT_GB} GB  (节省 ${RATIO}%)"
