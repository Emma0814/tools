#!/usr/bin/env python3
"""自动从夸克网盘提取 Cookie 并写入 ~/.kuake.env

首次运行：打开浏览器，等用户扫码登录
后续运行：自动复用登录态，直接提取 Cookie

浏览器 profile 固定存放在 ~/.quark-profile，脚本移动位置不丢登录态。
Cookie 写入 ~/.kuake.env（全局凭证，不随脚本目录走）。

用法:
  python3 grab-quark-cookie.py              # 有头模式（首次登录用）
  python3 grab-quark-cookie.py --headless   # 无头模式（复用登录态）
"""

import json
import os
import re
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

SCRIPT_DIR = Path(__file__).parent
ENV_FILE = Path.home() / ".kuake.env"
PROFILE_DIR = Path.home() / ".quark-profile"

QUARK_URL = "https://pan.quark.cn"
COOKIE_URLS = [
    "https://pan.quark.cn",
    "https://drive-pc.quark.cn",
    "https://b.quark.cn",
    "https://access-open.quark.cn",
]
KUAKE_COOKIE_KEY = "KUAKE_COOKIE"


def extract_cookie_string(context) -> str:
    cookies = context.cookies(COOKIE_URLS)
    parts = []
    seen = set()
    for c in cookies:
        name = c["name"]
        value = c["value"]
        if name in seen or not value:
            continue
        seen.add(name)
        parts.append(f"{name}={value}")
    return "; ".join(parts)


def verify_cookie(cookie_str: str):
    import subprocess
    env = {**os.environ, "KUAKE_COOKIE": cookie_str}
    try:
        result = subprocess.run(
            ["kuake", "user"],
            capture_output=True, text=True, timeout=15, env=env,
        )
        data = json.loads(result.stdout)
        if data.get("success"):
            return data["data"]
    except Exception:
        pass
    return None


def update_env(cookie_str: str):
    if ENV_FILE.exists():
        content = ENV_FILE.read_text()
        if KUAKE_COOKIE_KEY + "=" in content:
            # 同时兼容 `KUAKE_COOKIE='...'` 和 `export KUAKE_COOKIE='...'` 两种格式
            content = re.sub(
                rf"(export\s+)?{KUAKE_COOKIE_KEY}='[^']*'",
                f"export {KUAKE_COOKIE_KEY}='{cookie_str}'",
                content,
            )
        else:
            content += f"\nexport {KUAKE_COOKIE_KEY}='{cookie_str}'\n"
        ENV_FILE.write_text(content)
    else:
        ENV_FILE.write_text(f"export {KUAKE_COOKIE_KEY}='{cookie_str}'\n")


def main():
    headless = "--headless" in sys.argv
    profile_exists = PROFILE_DIR.exists() and any(PROFILE_DIR.iterdir())

    if headless and not profile_exists:
        print("❌ 无登录态，首次运行请不加 --headless")
        sys.exit(1)

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(PROFILE_DIR),
            headless=headless,
            viewport={"width": 1280, "height": 800},
            locale="zh-CN",
        )

        page = context.pages[0] if context.pages else context.new_page()
        page.goto(QUARK_URL, wait_until="networkidle", timeout=30000)
        time.sleep(2)

        is_logged_in = False
        for _ in range(3):
            cookies = context.cookies(COOKIE_URLS)
            cookie_names = {c["name"] for c in cookies}
            if "__pus" in cookie_names or "__puus" in cookie_names:
                is_logged_in = True
                break
            time.sleep(1)

        if not is_logged_in and not headless:
            print("⏳ 等待扫码登录... (最长 120 秒)")
            for i in range(120):
                time.sleep(1)
                cookies = context.cookies(COOKIE_URLS)
                cookie_names = {c["name"] for c in cookies}
                if "__pus" in cookie_names or "__puus" in cookie_names:
                    is_logged_in = True
                    break
                if i % 10 == 0 and i > 0:
                    print(f"  还在等待... ({i}s)")

        if not is_logged_in:
            print("❌ 登录超时或未检测到登录态")
            context.close()
            sys.exit(1)

        print("✅ 检测到登录态，提取 Cookie...")
        cookie_str = extract_cookie_string(context)
        context.close()

    if not cookie_str:
        print("❌ 提取到的 Cookie 为空")
        sys.exit(1)

    print(f"📦 提取到 {len(cookie_str)} 字符的 Cookie")

    print("🔍 验证 Cookie...")
    user_info = verify_cookie(cookie_str)
    if user_info:
        print(f"✅ 验证成功 | 账号: {user_info['nickname']} ({user_info['member_type']})")
    else:
        print("⚠️  验证失败，仍将写入 ~/.kuake.env（可能 kuake CLI 不需要全部 Cookie）")

    update_env(cookie_str)
    print(f"✅ 已写入 {ENV_FILE}")


if __name__ == "__main__":
    main()
