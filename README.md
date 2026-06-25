# Sandbox Tools

公共工具集，跨项目复用。

## feishu-tools.sh

飞书通用能力脚本，覆盖 IM 消息、云盘、文档、日历、任务、知识库。

**两种使用方式**：

```bash
# 1. source 库模式（其他脚本 source 后调用函数）
source ~/jsh/Sandbox/tools/feishu-tools.sh
feishu_send_text "hello" --chat-id oc_xxx
feishu_upload "report.pdf"  # → file_token
feishu_create_docx "summary.md" "周报"  # → docx_url

# 2. CLI 模式（直接命令行调用）
~/jsh/Sandbox/tools/feishu-tools.sh send "hello" --chat-id oc_xxx
~/jsh/Sandbox/tools/feishu-tools.sh upload "report.pdf"
~/jsh/Sandbox/tools/feishu-tools.sh create-event "会议" "2026-06-24T14:00:00+08:00" "2026-06-24T15:00:00+08:00"
```

**环境变量**：
- `FEISHU_CHAT_ID` — 默认聊天 ID（免每次传 `--chat-id`）
- `FEISHU_AS` — 默认身份 `user`（默认）| `bot`

**前置要求**：`lark-cli` 已登录 + `jq` 已安装。

**完整命令列表**：`./feishu-tools.sh help`

## transcode-720p.sh

视频转码，保留原始比例，短边缩到 720。自动识别横屏/竖屏。

```bash
# 单个文件（输出到同目录，-720p 后缀）
~/jsh/Sandbox/tools/transcode-720p.sh /Users/jingshuhui/Downloads/aliyunpan/来自分享/锅师小课/xxx.mp4

# 指定输出路径
~/jsh/Sandbox/tools/transcode-720p.sh /Users/jingshuhui/Downloads/aliyunpan/来自分享/锅师小课/xxx.mp4 /Users/jingshuhui/Downloads/aliyunpan/来自分享/锅师小课/xxx_720p.mp4
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
