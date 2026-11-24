#!/usr/bin/env bash
# monitor_hongguo_all.sh
# 同時監控 guoapp-modules/hongguo 的 Release 與 Commit
# 需：gh (已登入)、jq、curl
# 環境變數：TELEGRAM_BOT_TOKEN、TELEGRAM_CHAT_ID

set -euo pipefail

#REPO="guoapp-modules/hongguo"
REPO="Xsummer/hongguo"
TG_API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

# 狀態檔
RELEASE_STATE="/tmp/hongguo_last_release.txt"
COMMIT_STATE="/tmp/hongguo_last_commit.txt"

# 發送 Telegram 訊息
send_tg() {
    local text="$1"
    curl -s -X POST "$TG_API" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d parse_mode="HTML" \
        -d disable_web_page_preview="true" \
        -d text="$text" >/dev/null
}

# 顏色輸出（終端機用）
log() { echo "[$(date '+%F %T')] $*"; }

# ========== 檢查 Release ==========
check_release() {
    log "檢查 Release..."
    local latest
    latest=$(gh release list -R "$REPO" --limit 1 --json tagName,name,publishedAt,isPrerelease --jq '
        .[0] | "\(.tagName)\t\(.name)\t\(.publishedAt)\t\(.isPrerelease)"
    ') || { log "❌ 取得 Release 失敗"; return; }

    local tag name published is_pre url
    tag=$(echo "$latest" | cut -f1)
    name=$(echo "$latest" | cut -f2)
    published=$(echo "$latest" | cut -f3)
    is_pre=$(echo "$latest" | cut -f4)
    url="https://github.com/${REPO}/releases/tag/${tag}"

    local last_tag=""
    [[ -f "$RELEASE_STATE" ]] && last_tag=$(cat "$RELEASE_STATE")

    if [[ "$tag" != "$last_tag" ]]; then
        local text="🚀 <b>${REPO} 新 Release</b>
📦 <b>版本：</b> <code>${tag}</code> (${name})
🏷️ <b>類型：</b> $([[ "$is_pre" == "true" ]] && echo "Pre-release" || echo "正式版")
🕒 <b>發布：</b> ${published}
🔗 <a href=\"${url}\">查看 Release 頁面</a>"

        send_tg "$text"
        echo "$tag" > "$RELEASE_STATE"
        log "✅ 推送新 Release：${tag}"
    else
        log "ℹ️ Release 無更新（目前 ${tag}）"
    fi
}

# ========== 檢查 Commit ==========
check_commit() {
    log "檢查 Commit..."
    local latest_sha latest_msg latest_url
    latest_sha=$(gh api repos/$REPO/commits --jq '.[0].sha') || { log "❌ 取得 Commit 失敗"; return; }
    latest_msg=$(gh api repos/$REPO/commits --jq '.[0].commit.message')
    latest_url="https://github.com/$REPO/commit/$latest_sha"

    local last_sha=""
    [[ -f "$COMMIT_STATE" ]] && last_sha=$(cat "$COMMIT_STATE")

    if [[ "$latest_sha" != "$last_sha" ]]; then
        local text="🔧 <b>${REPO} 新 Commit</b>
📝 <code>${latest_sha:0:8}</code> ${latest_msg}
🔗 <a href=\"${latest_url}\">查看差異</a>"

        send_tg "$text"
        echo "$latest_sha" > "$COMMIT_STATE"
        log "✅ 推送新 Commit：${latest_sha:0:8} - ${latest_msg}"
    else
        log "ℹ️ Commit 無更新（目前 ${latest_sha:0:8}）"
    fi
}

# ========== 主程式 ==========
main() {
    log "=== 開始檢查 ${REPO} ==="
    check_release
    check_commit
    log "=== 檢查完成 ==="
}

main "$@"
