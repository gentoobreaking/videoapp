#!/usr/bin/env bash
# monitor_hongguo_release.sh
# 用法：./monitor_hongguo_release.sh
# 需：gh (已登入)、jq、curl
# 環境變數：TELEGRAM_BOT_TOKEN、TELEGRAM_CHAT_ID

set -euo pipefail

#REPO="guoapp-modules/hongguo"
REPO="Xsummer/hongguo"
STATE_FILE="/tmp/hongguo_last_release.txt"
TG_API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

TELEGRAM_CHAT_ID=6748222184

# 取得最新 release（含 pre-release）
latest=$(gh release list -R "$REPO" --limit 1 --json tagName,name,publishedAt,isPrerelease --jq '
  .[0] | "\(.tagName)\t\(.name)\t\(.publishedAt)\t\(.isPrerelease)"
')

tag=$(echo "$latest" | cut -f1)
name=$(echo "$latest" | cut -f2)
published=$(echo "$latest" | cut -f3)
is_pre=$(echo "$latest" | cut -f4)
url="https://github.com/${REPO}/releases/tag/${tag}"

# 讀取上次記錄
last_tag=""
[[ -f "$STATE_FILE" ]] && last_tag=$(cat "$STATE_FILE")

if [[ "$tag" != "$last_tag" ]]; then
  # 新 release，發 Telegram
  text="🚀 <b>guoapp-modules/hongguo 新 Release</b>
📦 <b>版本：</b> <code>${tag}</code> (${name})
🏷️ <b>類型：</b> $([[ "$is_pre" == "true" ]] && echo "Pre-release" || echo "正式版")
🕒 <b>發布：</b> ${published}
🔗 <a href=\"${url}\">查看 Release 頁面</a>"

  curl -s -X POST "$TG_API" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d parse_mode="HTML" \
    -d disable_web_page_preview="true" \
    -d text="$text" >/dev/null

  # 更新狀態
  echo "$tag" > "$STATE_FILE"
  echo "[$(date)] 推送新版本：$tag"
else
  echo "[$(date)] 無新版本（目前 $tag）"
fi
