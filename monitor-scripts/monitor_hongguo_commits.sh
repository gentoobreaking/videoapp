#!/usr/bin/env bash
# monitor_hongguo_commits.sh
# 監控 guoapp-modules/hongguo 新 commit 並發 Telegram
# 需：gh (已登入)、jq、curl
# 環境變數：TELEGRAM_BOT_TOKEN、TELEGRAM_CHAT_ID

set -euo pipefail

#REPO="guoapp-modules/hongguo"
REPO="Xsummer/hongguo"
STATE_FILE="/tmp/hongguo_last_commit.txt"
TG_API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

# 取得最新 commit
latest_sha=$(gh api repos/$REPO/commits --jq '.[0].sha')
latest_msg=$(gh api repos/$REPO/commits --jq '.[0].commit.message')
latest_url="https://github.com/$REPO/commit/$latest_sha"

# 讀取上次記錄
last_sha=""
[[ -f "$STATE_FILE" ]] && last_sha=$(cat "$STATE_FILE")

if [[ "$latest_sha" != "$last_sha" ]]; then
  # 新 commit，發 Telegram
  text="🔧 <b>hongguo 新 Commit</b>
📝 <code>${latest_sha:0:8}</code> ${latest_msg}
🔗 <a href=\"${latest_url}\">查看差異</a>"

  curl -s -X POST "$TG_API" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d parse_mode="HTML" \
    -d text="$text" >/dev/null

  # 更新狀態
  echo "$latest_sha" > "$STATE_FILE"
  echo "[$(date)] 推送新 Commit：${latest_sha:0:8} - ${latest_msg}"
else
  echo "[$(date)] 無新 Commit（目前 ${latest_sha:0:8}）"
fi
