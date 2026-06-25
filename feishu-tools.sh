#!/bin/bash
# ==========================================================================
# feishu-tools.sh — 飞书通用能力脚本
# ==========================================================================
# 两种使用方式：
#   1. source 库模式：source feishu-tools.sh; feishu_send_text "hello"
#   2. CLI 模式：    ./feishu-tools.sh send "hello" --chat-id oc_xxx
#
# 前置要求：
#   - lark-cli 已登录（lark-cli auth login）
#   - jq 已安装
#
# 环境变量（可选）：
#   FEISHU_CHAT_ID  默认聊天 ID（免每次传 --chat-id）
#   FEISHU_AS       默认身份：user（默认）| bot
# ==========================================================================

set -o pipefail

# --- 日志函数 ---------------------------------------------------------------
if ! declare -F _feishu_log >/dev/null 2>&1; then
  _feishu_log() { echo "[feishu $(date '+%H:%M:%S')] $*" >&2; }
fi

# --- 默认配置 ---------------------------------------------------------------
: "${FEISHU_AS:=user}"
: "${FEISHU_CHAT_ID:=}"

# --- 内部工具 ---------------------------------------------------------------
_feishu_jq_ok() {
  jq -e '(.ok == true) or (.code == 0)' 2>/dev/null | grep -q true
}

_feishu_jq_field() {
  local field="$1" default="${2:-}"
  local val
  val=$(jq -r "${field} // empty" 2>/dev/null) || true
  echo "${val:-${default}}"
}

# ==========================================================================
# 1. IM 消息
# ==========================================================================

# feishu_send_text <text> [--chat-id <id>] [--as bot|user]
feishu_send_text() {
  local text="" chat_id="${FEISHU_CHAT_ID}" as="${FEISHU_AS}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --chat-id) chat_id="$2"; shift 2 ;;
      --as)      as="$2";      shift 2 ;;
      *)         text="$1";    shift   ;;
    esac
  done
  [[ -z "${text}" ]] && { _feishu_log "ERROR: feishu_send_text 需要 text 参数"; return 1; }
  [[ -z "${chat_id}" ]] && { _feishu_log "ERROR: feishu_send_text 需要 --chat-id 或设置 FEISHU_CHAT_ID"; return 1; }

  local resp
  resp=$(lark-cli im +messages-send \
    --as "${as}" \
    --chat-id "${chat_id}" \
    --text "${text}" 2>/dev/null) || {
    _feishu_log "WARN 发送消息失败: ${resp:0:200}"
    return 1
  }
  echo "${resp}" | _feishu_jq_ok || {
    _feishu_log "WARN 消息响应异常: ${resp:0:200}"
    return 1
  }
  return 0
}

# feishu_send_file <path> [--chat-id <id>] [--file-type file|image|audio]
# 先上传文件到云空间，再发到聊天。成功输出 message_id
feishu_send_file() {
  local path="" chat_id="${FEISHU_CHAT_ID}" file_type="file"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --chat-id)   chat_id="$2";   shift 2 ;;
      --file-type) file_type="$2";  shift 2 ;;
      *)           path="$1";       shift   ;;
    esac
  done
  [[ -z "${path}" ]] && { _feishu_log "ERROR: feishu_send_file 需要文件路径"; return 1; }
  [[ ! -f "${path}" ]] && { _feishu_log "ERROR: 文件不存在: ${path}"; return 1; }
  [[ -z "${chat_id}" ]] && { _feishu_log "ERROR: 需要 --chat-id 或设置 FEISHU_CHAT_ID"; return 1; }

  local dir base resp
  dir="${path%/*}"; base="${path##*/}"
  [[ "${dir}" == "${path}" ]] && dir="."

  resp=$(cd "${dir}" && lark-cli im +messages-send \
    --as user \
    --chat-id "${chat_id}" \
    --file-type "${file_type}" \
    --file "./${base}" 2>/dev/null) || {
    _feishu_log "WARN 发送文件失败: ${resp:0:200}"
    return 1
  }
  echo "${resp}" | _feishu_jq_ok || {
    _feishu_log "WARN 文件消息响应异常: ${resp:0:200}"
    return 1
  }
  echo "${resp}" | _feishu_jq_field '.data.message_id'
  return 0
}

# ==========================================================================
# 2. 云盘（Drive）
# ==========================================================================

# feishu_upload <path> → file_token
feishu_upload() {
  local path="$1"
  [[ -z "${path}" ]] && { _feishu_log "ERROR: feishu_upload 需要文件路径"; return 1; }
  [[ ! -f "${path}" ]] && { _feishu_log "ERROR: 文件不存在: ${path}"; return 1; }

  local dir base resp
  dir="${path%/*}"; base="${path##*/}"
  [[ "${dir}" == "${path}" ]] && dir="."

  # lark-cli 安全限制：--file 必须是当前目录下的相对路径
  resp=$(cd "${dir}" && lark-cli drive +upload \
    --as user \
    --file "./${base}" 2>/dev/null) || {
    _feishu_log "WARN 上传失败: ${resp:0:200}"
    return 1
  }

  local file_token
  file_token=$(echo "${resp}" | _feishu_jq_field '.data.file_token')
  if [[ -z "${file_token}" ]]; then
    _feishu_log "WARN 上传无 file_token: ${resp:0:200}"
    return 1
  fi
  echo "${file_token}"
  return 0
}

# feishu_download <file_token> [output_path]
feishu_download() {
  local file_token="$1" output="${2:-}"
  [[ -z "${file_token}" ]] && { _feishu_log "ERROR: feishu_download 需要 file_token"; return 1; }

  local resp
  resp=$(lark-cli drive +download \
    --as user \
    --file-token "${file_token}" \
    ${output:+--output "${output}"} 2>/dev/null) || {
    _feishu_log "WARN 下载失败: ${resp:0:200}"
    return 1
  }
  echo "${resp}" | _feishu_jq_ok || {
    _feishu_log "WARN 下载响应异常: ${resp:0:200}"
    return 1
  }
  echo "${resp}" | _feishu_jq_field '.data.file_path // empty'
  return 0
}

# feishu_file_url <file_token> → https://my.feishu.cn/file/<token>
feishu_file_url() {
  local file_token="$1"
  [[ -z "${file_token}" ]] && { _feishu_log "ERROR: feishu_file_url 需要 file_token"; return 1; }
  echo "https://my.feishu.cn/file/${file_token}"
}

# feishu_file_info <file_token> → JSON
feishu_file_info() {
  local file_token="$1"
  [[ -z "${file_token}" ]] && { _feishu_log "ERROR: feishu_file_info 需要 file_token"; return 1; }

  lark-cli drive +metas-batch-query \
    --as user \
    --file-tokens "${file_token}" 2>/dev/null
}

# ==========================================================================
# 3. 文档（Docx）
# ==========================================================================

# feishu_create_docx <md_path> <title> → docx_url
feishu_create_docx() {
  local md_path="$1" title="$2"
  [[ -z "${md_path}" ]] && { _feishu_log "ERROR: feishu_create_docx 需要 markdown 文件路径"; return 1; }
  [[ ! -f "${md_path}" ]] && { _feishu_log "ERROR: 文件不存在: ${md_path}"; return 1; }
  [[ -z "${title}" ]] && title="$(basename "${md_path}" .md)"

  local dir base resp
  dir="${md_path%/*}"; base="${md_path##*/}"
  [[ "${dir}" == "${md_path}" ]] && dir="."

  resp=$(cd "${dir}" && lark-cli docs +create \
    --as user \
    --title "${title}" \
    --markdown "@./${base}" 2>/dev/null) || {
    _feishu_log "WARN 创建 docx 失败: ${resp:0:300}"
    return 1
  }

  local url token
  url=$(echo "${resp}" | _feishu_jq_field '.data.doc_url // .data.url')
  if [[ -z "${url}" ]]; then
    token=$(echo "${resp}" | _feishu_jq_field '.data.doc_id // .data.document_id')
    if [[ -n "${token}" ]]; then
      url="https://www.feishu.cn/docx/${token}"
    fi
  fi
  if [[ -z "${url}" ]]; then
    _feishu_log "WARN 创建 docx 无 url/token: ${resp:0:400}"
    return 1
  fi
  echo "${url}"
  return 0
}

# feishu_overwrite_docx <docx_url> <md_path> <title>
# 覆盖已有 docx 内容（用 markdown 替换）
feishu_overwrite_docx() {
  local docx_url="$1" md_path="$2" title="${3:-}"
  [[ -z "${docx_url}" ]] && { _feishu_log "ERROR: feishu_overwrite_docx 需要 docx_url"; return 1; }
  [[ -z "${md_path}" ]] && { _feishu_log "ERROR: feishu_overwrite_docx 需要 markdown 文件路径"; return 1; }
  [[ ! -f "${md_path}" ]] && { _feishu_log "ERROR: 文件不存在: ${md_path}"; return 1; }

  local resp
  resp=$(lark-cli docs +update \
    --as user \
    --doc "${docx_url}" \
    --mode overwrite \
    --markdown "@${md_path}" \
    ${title:+--new-title "${title}"} 2>/dev/null) || {
    _feishu_log "WARN 覆盖 docx 失败: ${resp:0:300}"
    return 1
  }
  echo "${resp}" | _feishu_jq_ok || {
    _feishu_log "WARN 覆盖 docx 响应异常: ${resp:0:300}"
    return 1
  }
  return 0
}

# feishu_read_docx <docx_url> → markdown
feishu_read_docx() {
  local docx_url="$1"
  [[ -z "${docx_url}" ]] && { _feishu_log "ERROR: feishu_read_docx 需要 docx_url"; return 1; }

  lark-cli docs +read \
    --as user \
    --doc "${docx_url}" \
    --format markdown 2>/dev/null
}

# feishu_search_docs <keyword> [--limit N]
feishu_search_docs() {
  local keyword="" limit="10"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      *)       keyword="$1"; shift ;;
    esac
  done
  [[ -z "${keyword}" ]] && { _feishu_log "ERROR: feishu_search_docs 需要关键词"; return 1; }

  lark-cli search +docs \
    --as user \
    --query "${keyword}" \
    --limit "${limit}" 2>/dev/null
}

# ==========================================================================
# 4. 日历
# ==========================================================================

# feishu_create_event <summary> <start_iso> <end_iso> [description] → event_id
feishu_create_event() {
  local summary="$1" start_iso="$2" end_iso="$3" description="${4:-}"
  [[ -z "${summary}" ]] && { _feishu_log "ERROR: feishu_create_event 需要 summary"; return 1; }
  [[ -z "${start_iso}" ]] && { _feishu_log "ERROR: feishu_create_event 需要 start_iso"; return 1; }
  [[ -z "${end_iso}" ]] && { _feishu_log "ERROR: feishu_create_event 需要 end_iso"; return 1; }

  local resp
  resp=$(lark-cli calendar +create \
    --as user \
    --summary "${summary}" \
    --description "${description}" \
    --start "${start_iso}" \
    --end "${end_iso}" 2>/dev/null) || {
    _feishu_log "WARN 创建日历事件失败: ${resp:0:200}"
    return 1
  }

  local event_id
  event_id=$(echo "${resp}" | _feishu_jq_field '.data.event_id')
  if [[ -z "${event_id}" ]]; then
    _feishu_log "WARN 日历事件无 event_id: ${resp:0:200}"
    return 1
  fi
  echo "${event_id}"
  return 0
}

# feishu_list_events [--from <date>] [--to <date>] → JSON
feishu_list_events() {
  local from="" to=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from) from="$2"; shift 2 ;;
      --to)   to="$2";   shift 2 ;;
      *)      shift ;;
    esac
  done

  lark-cli calendar +agenda \
    --as user \
    ${from:+--from "${from}"} \
    ${to:+--to "${to}"} 2>/dev/null
}

# ==========================================================================
# 5. 任务
# ==========================================================================

# feishu_create_task <summary> [--description <desc>] [--due <date>] → task_id
feishu_create_task() {
  local summary="" description="" due=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --description) description="$2"; shift 2 ;;
      --due)         due="$2";         shift 2 ;;
      *)             summary="$1";      shift   ;;
    esac
  done
  [[ -z "${summary}" ]] && { _feishu_log "ERROR: feishu_create_task 需要 summary"; return 1; }

  local resp
  resp=$(lark-cli task +create \
    --as user \
    --summary "${summary}" \
    ${description:+--description "${description}"} \
    ${due:+--due "${due}"} 2>/dev/null) || {
    _feishu_log "WARN 创建任务失败: ${resp:0:200}"
    return 1
  }

  echo "${resp}" | _feishu_jq_field '.data.task_id'
  return 0
}

# feishu_list_tasks [--status pending|completed] → JSON
feishu_list_tasks() {
  local status=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) status="$2"; shift 2 ;;
      *)        shift ;;
    esac
  done

  lark-cli task +get-my-tasks \
    --as user \
    ${status:+--status "${status}"} 2>/dev/null
}

# feishu_complete_task <task_id>
feishu_complete_task() {
  local task_id="$1"
  [[ -z "${task_id}" ]] && { _feishu_log "ERROR: feishu_complete_task 需要 task_id"; return 1; }

  local resp
  resp=$(lark-cli task +complete \
    --as user \
    --task-id "${task_id}" 2>/dev/null) || {
    _feishu_log "WARN 完成任务失败: ${resp:0:200}"
    return 1
  }
  echo "${resp}" | _feishu_jq_ok || {
    _feishu_log "WARN 完成任务响应异常: ${resp:0:200}"
    return 1
  }
  return 0
}

# ==========================================================================
# 6. 知识库（Wiki）
# ==========================================================================

# feishu_list_wikis → JSON
feishu_list_wikis() {
  lark-cli wiki +list --as user 2>/dev/null
}

# feishu_wiki_tree <wiki_token> → JSON
feishu_wiki_tree() {
  local wiki_token="$1"
  [[ -z "${wiki_token}" ]] && { _feishu_log "ERROR: feishu_wiki_tree 需要 wiki_token"; return 1; }

  lark-cli wiki +tree \
    --as user \
    --wiki-token "${wiki_token}" 2>/dev/null
}

# ==========================================================================
# 7. 用户/通讯录
# ==========================================================================

# feishu_user_info [email|name] → JSON
feishu_user_info() {
  local query="${1:-me}"
  lark-cli user +resolve --as user "${query}" 2>/dev/null
}

# ==========================================================================
# 8. 综合操作
# ==========================================================================

# feishu_upload_and_share <path> → "file_token<TAB>url"
# 上传文件到云盘，返回 file_token 和分享链接
feishu_upload_and_share() {
  local path="$1"
  local file_token
  file_token=$(feishu_upload "${path}") || return 1
  local url
  url=$(feishu_file_url "${file_token}")
  printf '%s\t%s\n' "${file_token}" "${url}"
}

# feishu_md_to_docx_and_share <md_path> <title> → docx_url
# 等价于 feishu_create_docx（别名，语义更清晰）
feishu_md_to_docx_and_share() {
  feishu_create_docx "$@"
}

# ==========================================================================
# CLI 入口
# ==========================================================================

_feishu_usage() {
  cat <<'EOF'
用法: feishu-tools.sh <命令> [参数]

IM 消息:
  send <text>              发送文本消息（需 FEISHU_CHAT_ID 或 --chat-id）
  send-file <path>         发送文件到聊天

云盘:
  upload <path>            上传文件，输出 file_token
  download <file_token>    下载文件
  file-url <file_token>    获取分享链接
  file-info <file_token>   查看文件元数据
  upload-share <path>      上传文件并获取分享链接

文档:
  create-docx <md> <title> 从 Markdown 创建飞书文档
  overwrite-docx <url> <md> 覆盖已有文档内容
  read-docx <url>          读取文档为 Markdown
  search-docs <keyword>    搜索文档

日历:
  create-event <title> <start> <end> [desc]  创建日历事件
  list-events              列出近期日程

任务:
  create-task <summary>    创建任务
  list-tasks               列出未完成任务
  complete-task <id>       完成任务

知识库:
  list-wikis               列出知识库
  wiki-tree <token>        查看知识库目录树

用户:
  user-info [email|name]   查询用户信息

环境变量:
  FEISHU_CHAT_ID           默认聊天 ID
  FEISHU_AS                默认身份（user|bot，默认 user）
EOF
}

# 主分发
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  CMD="${1:-}"
  shift 2>/dev/null || true

  case "${CMD}" in
    # IM
    send)              feishu_send_text "$@" ;;
    send-file)         feishu_send_file "$@" ;;
    # Drive
    upload)            feishu_upload "$@" ;;
    download)          feishu_download "$@" ;;
    file-url)          feishu_file_url "$@" ;;
    file-info)         feishu_file_info "$@" ;;
    upload-share)      feishu_upload_and_share "$@" ;;
    # Docx
    create-docx)       feishu_create_docx "$@" ;;
    overwrite-docx)    feishu_overwrite_docx "$@" ;;
    read-docx)         feishu_read_docx "$@" ;;
    search-docs)       feishu_search_docs "$@" ;;
    # Calendar
    create-event)      feishu_create_event "$@" ;;
    list-events)       feishu_list_events "$@" ;;
    # Task
    create-task)       feishu_create_task "$@" ;;
    list-tasks)        feishu_list_tasks "$@" ;;
    complete-task)     feishu_complete_task "$@" ;;
    # Wiki
    list-wikis)        feishu_list_wikis "$@" ;;
    wiki-tree)         feishu_wiki_tree "$@" ;;
    # User
    user-info)         feishu_user_info "$@" ;;
    # Help
    ""|-h|--help|help) _feishu_usage ;;
    *)
      echo "未知命令: ${CMD}" >&2
      _feishu_usage
      exit 64
      ;;
  esac
fi