# tools

通用工具集，跨项目复用。

## transcode-720p.sh

将视频短边缩放到 720p，保留原始横纵比。

```
transcode-720p.sh <input.mp4> <output.mp4>
```

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
