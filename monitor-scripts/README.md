# Hongguo 監控腳本集合

監控 `guoapp-modules/hongguo` 的 **Release** 與 **Commit**，發送 Telegram 通知。

## 📁 腳本列表

| 檔案 | 功能 | 狀態檔 |
|------|------|--------|
| `monitor_hongguo_release.sh` | 單獨監控 Release | `/tmp/hongguo_last_release.txt` |
| `monitor_hongguo_commits.sh` | 單獨監控 Commit | `/tmp/hongguo_last_commit.txt` |
| `monitor_hongguo_all.sh` | **同時監控 Release + Commit**（推薦） | 兩個各自獨立 |

---

## 🚀 快速開始

### 1. 建立 Telegram Bot
```bash
# 1. 跟 @BotFather 開 Bot，拿到 BOT_TOKEN
# 2. 把 Bot 加進群組或私聊，發一句話
# 3. 取得 Chat ID：
curl "https://api.telegram.org/bot<BOT_TOKEN>/getUpdates" | jq '.result[].message.chat.id'
```

### 2. 設定環境變數
```bash
export TELEGRAM_BOT_TOKEN="你的_BOT_TOKEN"
export TELEGRAM_CHAT_ID="你的_CHAT_ID"  # 例如 6748222184
```

### 3. 測試跑一次
```bash
cd /Users/david/Projects/videoapp/monitor-scripts
./monitor_hongguo_all.sh
```

預期輸出：
```
[2026-11-23 20:08:29] === 開始檢查 guoapp-modules/hongguo ===
[2026-11-23 20:08:29] 檢查 Release...
[2026-11-23 20:08:29] ℹ️ Release 無更新（目前 v1.0.7）
[2026-11-23 20:08:29] 檢查 Commit...
[2026-11-23 20:08:31] ℹ️ Commit 無更新（目前 cdf8a24b）
[2026-11-23 20:08:31] === 檢查完成 ===
```

---

## 🔧 三種部署方式

### 方式一：`watch` 臨時觀察（開發機、臨時 SSH）
```bash
# 前景跑，每 10 分鐘（600 秒）檢查一次
watch -n 600 ./monitor_hongguo_all.sh

# 或背景跑，關終端機也不死
nohup watch -n 600 ./monitor_hongguo_all.sh >> ~/hongguo_all.log 2>&1 &
```

### 方式二：systemd Timer（生產環境推薦，7×24 自動）

```bash
# 1. 腳本安裝到系統路徑
sudo install -m 755 /Users/david/Projects/videoapp/monitor-scripts/monitor_hongguo_all.sh /usr/local/bin/

# 2. 建立服務單元
sudo tee /etc/systemd/system/hongguo-all-monitor.service >/dev/null <<'EOF'
[Unit]
Description=Monitor guoapp-modules/hongguo releases & commits
After=network-online.target

[Service]
Type=oneshot
Environment=TELEGRAM_BOT_TOKEN=你的_BOT_TOKEN
Environment=TELEGRAM_CHAT_ID=6748222184
ExecStart=/usr/local/bin/monitor_hongguo_all.sh
EOF

# 3. 建立定時器（每 5 分鐘）
sudo tee /etc/systemd/system/hongguo-all-monitor.timer >/dev/null <<'EOF'
[Unit]
Description=Check hongguo releases & commits every 5 minutes

[Timer]
OnBootSec=3min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 4. 啟用
sudo systemctl daemon-reload
sudo systemctl enable --now hongguo-all-monitor.timer

# 5. 查看狀態
systemctl list-timers | grep hongguo
journalctl -u hongguo-all-monitor -f
```

### 方式三：無 root 權限的伺服器/容器
```bash
# crontab 每 5 分鐘
*/5 * * * * /path/to/monitor_hongguo_all.sh >> /path/to/hongguo_all.log 2>&1

# 或 @reboot 配合 nohup
@reboot nohup watch -n 300 /path/to/monitor_hongguo_all.sh >> /path/to/hongguo_all.log 2>&1 &
```

---

## 📊 監控目標對比

| 監控層級 | 時效性 | 觸發條件 | 適合場景 |
|----------|--------|----------|----------|
| **Commits** | 秒級 | 作者 `git push` 即觸發 | 最早得知作者在修什麼（簽名/接口/設備註冊） |
| **Releases** | 分鐘級 | 作者打 tag 發布正式版 | 知道哪個版本可以直接下載/更新模塊 |
| **hongguo-tv-releases** | 分鐘級 | APK 發布 | 只要 Android TV/手機 APK |

> **建議**：兩個都跑——Release 給「正式可用版本」，Commit 給「作者正在修什麼」。`monitor_hongguo_all.sh` 已同時處理兩者。

---

## 🔑 關鍵實作細節

### Release 監控
```bash
# gh release list 不提供 url 欄位，需自行拼裝
latest=$(gh release list -R "$REPO" --limit 1 \
  --json tagName,name,publishedAt,isPrerelease \
  --jq '.[0] | "\(.tagName)\t\(.name)\t\(.publishedAt)\t\(.isPrerelease)"')

url="https://github.com/${REPO}/releases/tag/${tag}"
```

### Commit 監控
```bash
# 直接用 GitHub API 取最新 commit
latest_sha=$(gh api repos/$REPO/commits --jq '.[0].sha')
latest_msg=$(gh api repos/$REPO/commits --jq '.[0].commit.message')
latest_url="https://github.com/$REPO/commit/$latest_sha"
```

### 狀態持久化
- Release：`/tmp/hongguo_last_release.txt`（記錄 tag）
- Commit：`/tmp/hongguo_last_commit.txt`（記錄 SHA）
- 兩者完全獨立，互不干擾

### 錯誤處理
- `gh` 指令失敗只印錯誤、不中斷另一項檢查
- `set -euo pipefail` 確保腳本健壯

---

## 📦 監控其他 Repo

修改腳本頂部的 `REPO` 變數即可：

```bash
# 監控 hongguo-tv-releases（APK 直裝版）
REPO="aston314/hongguo-tv-releases"

# 監控其他 guoapp-modules 下的站源
REPO="guoapp-modules/huangguoai"
REPO="guoapp-modules/yeguo"
```

---

## 🛠 依賴工具

| 工具 | 安裝方式 |
|------|----------|
| `gh` | `brew install gh` → `gh auth login` |
| `jq` | `brew install jq` |
| `curl` | 內建 |

---

## 📝 更新記錄

- **2026-11-23** 新增 `monitor_hongguo_all.sh` 合併監控 Release + Commit
- **2026-11-23** 修正 Release 監控 JSON 欄位（移除不存在的 `url`，改用自行拼裝）
- **2026-11-23** 修正 Commit 監控輸出訊息（新增「無新 Commit」狀態列印）
- **2026-11-23** 修正 `gh release list` 陣列取值（加 `.[0] |`）