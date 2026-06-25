# Sandbox Tools

公共工具集，跨项目复用。

## feishu-tools.sh

lark-cli 的 bash 封装，供脚本 source 后调用。前置：lark-cli 已登录 + jq。

## transcode-720p.sh

视频转码，保留原始比例，短边缩到 720。自动识别横屏/竖屏。

```bash
# 单个文件（输出到同目录，-720p 后缀）
./transcode-720p.sh ~/Downloads/video.mp4

# 指定输出路径
./transcode-720p.sh ~/Downloads/video.mp4 ~/Downloads/video_720p.mp4
```

- 横屏：`*×720`（高 720，宽自动）
- 竖屏：`720×*`（宽 720，高自动）
- 编码：h264_videotoolbox（Apple Silicon 硬件加速）
- 音频：直接复制，不重编码

## kuake/

夸克网盘工具集：Cookie 抓取/校验/定时刷新 + 文件上传。

前置依赖：

- `kuake` CLI、`playwright`
- 全局凭证 `~/.kuake.env`：`export KUAKE_COOKIE='...'`
- 浏览器登录态 `~/.quark-profile`（首次扫码生成）

```sh
# 抓取夸克 Cookie → ~/.kuake.env（首次有头扫码，后续 --headless 复用）
python3 kuake/grab-quark-cookie.py [--headless]

# 校验 Cookie 有效性，--auto-update 失效时自动刷新
kuake/check-quark-cookie.sh [--auto-update]

# 上传文件到夸克网盘（自动建目录 + 响应判定真实成功）
kuake/kuake-upload.sh <local_file> <quark_path>

# cron 定时刷新 Cookie（每周一 10:00）
kuake/refresh-cookie-cron.sh
```
