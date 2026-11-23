有 release，且作者打 tag 很及时（commit 後幾分鐘就會 release）。可以寫成定時腳本 + Telegram Bot 推送。

---

## 📋 完整方案：GitHub Release 監控 + Telegram 推送

### 1. 先建 Telegram Bot & 取得 Chat ID

```bash
# 1. 跟 @BotFather 開 Bot，拿到 BOT_TOKEN
# 2. 把 Bot 加進群組或私聊，發一句話
# 3. 取得 Chat ID：
curl "https://api.telegram.org/bot<BOT_TOKEN>/getUpdates" | jq '.result[].message.chat.id'
```

### 2. 監控腳本 `monitor_hongguo_release.sh`

```bash
#!/usr/bin/env bash
# monitor_hongguo_release.sh
# 用法：./monitor_hongguo_release.sh
# 需：gh (已登入)、jq、curl
# 環境變數：TELEGRAM_BOT_TOKEN、TELEGRAM_CHAT_ID

set -euo pipefail

REPO="guoapp-modules/hongguo"
STATE_FILE="/tmp/hongguo_last_release.txt"
TG_API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

# 取得最新 release（含 pre-release）
latest=$(gh release list -R "$REPO" --limit 1 --json tagName,name,publishedAt,url,isPrerelease --jq '
  "\(.tagName)\t\(.name)\t\(.publishedAt)\t\(.url)\t\(.isPrerelease)"
')

tag=$(echo "$latest" | cut -f1)
name=$(echo "$latest" | cut -f2)
published=$(echo "$latest" | cut -f3)
url=$(echo "$latest" | cut -f4)
is_pre=$(echo "$latest" | cut -f5)

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
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d parse_mode="HTML" \
    -d disable_web_page_preview="true" \
    -d text="$text" >/dev/null

  # 更新狀態
  echo "$tag" > "$STATE_FILE"
  echo "[$(date)] 推送新版本：$tag"
else
  echo "[$(date)] 無新版本（目前 $tag）"
fi
```

### 3. systemd Timer 實現「每 5 分鐘檢查一次」

**`/etc/systemd/system/hongguo-monitor.service`**
```ini
[Unit]
Description=Monitor guoapp-modules/hongguo releases
After=network-online.target

[Service]
Type=oneshot
Environment=TELEGRAM_BOT_TOKEN=你的_BOT_TOKEN
Environment=TELEGRAM_CHAT_ID=你的_CHAT_ID
ExecStart=/usr/local/bin/monitor_hongguo_release.sh
```

**`/etc/systemd/system/hongguo-monitor.timer`**
```ini
[Unit]
Description=Check hongguo releases every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
# 安裝腳本
sudo install -m 755 monitor_hongguo_release.sh /usr/local/bin/

# 載入並啟用
sudo systemctl daemon-reload
sudo systemctl enable --now hongguo-monitor.timer

# 查看狀態
systemctl list-timers | grep hongguo
journalctl -u hongguo-monitor -f
```

---

## 🔄 進階：同時監控 **Commits**（比 Release 更早知道有修復）

作者有時 commit 修復後幾分鐘才打 tag。若想**最快秒級感知**，改監控 `commits`：

```bash
#!/usr/bin/env bash
# monitor_hongguo_commits.sh
REPO="guoapp-modules/hongguo"
STATE_FILE="/tmp/hongguo_last_commit.txt"

latest_sha=$(gh api repos/$REPO/commits --jq '.[0].sha')
latest_msg=$(gh api repos/$REPO/commits --jq '.[0].commit.message')
latest_url="https://github.com/$REPO/commit/$latest_sha"

last_sha=""
[[ -f "$STATE_FILE" ]] && last_sha=$(cat "$STATE_FILE")

if [[ "$latest_sha" != "$last_sha" ]]; then
  text="🔧 <b>hongguo 新 Commit</b>
📝 <code>${latest_sha:0:8}</code> ${latest_msg}
🔗 <a href=\"${latest_url}\">查看差異</a>"

  curl -s -X POST "$TG_API" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d parse_mode="HTML" \
    -d text="$text" >/dev/null

  echo "$latest_sha" > "$STATE_FILE"
fi
```

> **建議**：兩個都跑——Release 給「正式可用版本」，Commit 給「作者正在修什麼」。

---

## 🧪 測試一下

```bash
# 手動跑一次看 Telegram 有沒收到
TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy /usr/local/bin/monitor_hongguo_release.sh
```

---

## 📦 如果只想監控 hongguo-tv-releases（APK 直裝版）

把 `REPO="aston314/hongguo-tv-releases"` 即可，同樣邏輯。

---

## ✅ 總結

| 監控目標 | 時效性 | 適合場景 |
|----------|--------|----------|
| **Release** | 分鐘級 | 正式可用版本、直接下載 APK/模塊 |
| **Commits** | 秒級 | 想第一時間知道作者改了什麼（签名/接口/設備註冊） |
| **hongguo-tv-releases** | 分鐘級 | 只要 Android TV/手機 APK |

腳本已給全，複製貼上、填 Token/Chat ID、丟 systemd timer 即可**完全自動化、免維護**。

---

## 臨時監控

## ✅ 優點

| 項目 | 說明 |
|------|------|
| **零設定** | 不需要 root、不寫 systemd unit、不用 `sudo` |
| **即時看到輸出** | 終端機直接印 `有新 Commit` / `無新 Commit`，適合**開發時臨時觀察** |
| **隨時 Ctrl+C 停止** | 不用 `systemctl stop/disable` |
| **適合 SSH 臨時掛著** | `tmux` / `screen` 丟背景跑幾小時 |

---

## ❌ 缺點（生產環境不建議）

| 問題 | 影響 |
|------|------|
| **終端機關掉就死** | SSH 斷線、關視窗、睡眠喚醒 → 監控中斷 |
| **無系統級持久化** | 重開機、登出、更新套件 → 都要手動重啟 |
| **無日誌輪轉** | `watch` 預設只保留最後一畫面，久了沒紀錄 |
| **無並發保護** | 若腳本跑超過 600 秒（網路卡頓），下一輪會疊上去 |
| **環境變數固化在 shell** | 換使用者/重新登入需重新 export `TELEGRAM_BOT_TOKEN` |
| **無健康檢查** | systemd 會自動重啟失敗的服務，`watch` 不會 |

---

## 🛠 如果一定要用 `watch`，建議加幾個保護

```bash
# 1. 用 nohup + 重導向 log，關終端機也不死
nohup watch -n 600 ./monitor_hongguo_commits.sh >> ~/hongguo_commits.log 2>&1 &

# 2. 或寫個 wrapper 防疊跑 + 記時間戳
#!/usr/bin/env bash
# monitor_hongguo_commits_wrapper.sh
LOCK="/tmp/hongguo_commits.lock"
exec 9>"$LOCK"
flock -n 9 || { echo "[$(date)] 上一輪未結束，跳過"; exit 0; }

echo "[$(date)] === 執行檢查 ==="
./monitor_hongguo_commits.sh
```

```bash
watch -n 600 ./monitor_hongguo_commits_wrapper.sh
```

---

## 📊 何時用哪個？

| 場景 | 推薦方式 |
|------|----------|
| **開發/除錯/臨時看幾小時** | `watch -n 600 ./monitor_hongguo_commits.sh`（或 `tmux` 跑著） |
| **長期 7×24 小時、要開機自動、要日誌、要自動重啟** | **systemd timer**（已幫你寫好） |
| **沒有 root 權限的伺服器/容器** | `nohup watch ...` + `crontab @reboot` 拉起 |
| **想同時看 Release + Commit 兩路輸出** | 兩個 `watch` 分兩個 pane（`tmux` 分割視窗） |

---

## 🎯 建議

> **開發機/桌機**：`tmux` 開兩個 pane，分別跑 `watch -n 600 ./monitor_hongguo_commits.sh` 和 `watch -n 600 ./monitor_hongguo_release.sh`，隨時可看、隨時可關。
>
> **伺服器/NAS/長期跑**：直接用 **systemd timer**（已給完整 unit 檔），一勞永逸、有 journald 可查、開機自動、掛了自動拉起。


