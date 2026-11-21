# hongguo-list CLI

紅果劇集搜尋與下載 CLI 工具，基於 videoapp 核心實現。

## 執行檔位置

```
./hongguo-list
```

### 最終目錄結構

```
.
├── hongguo-list                    # CLI 執行檔
├── data/
│   ├── downloads/                  # ✅ 實際下載目錄 (含 index.json)
│   │   ├── index.json              # 持久化任務狀態
│   │   └── <series_id>/            # 各劇集下載目錄
│   ├── cache/                      # 快取目錄
│   └── modules/
│       └── hongguo/                # 模組目錄 (手動複製自 video-src/hongguo)
└── native/cmd/hongguo-list/main.go  # CLI 源碼
```

## 完整功能清單

### 基本用法

```bash
# 基本用法
./hongguo-list -q "關鍵字"              # 顯示搜尋結果
./hongguo-list -q "關鍵字" -n 3         # 選擇第 3 個
./hongguo-list -q "關鍵字" -n 3 -d      # 背景下載到 ~/Projects/videoapp/data/downloads
./hongguo-list -q "關鍵字" -n 3 -d -o ./my_dir  # 指定輸出目錄
./hongguo-list -q "關鍵字" -all         # 僅顯示搜尋結果

# 下載管理 (需 -q 指定劇集)
./hongguo-list -q "關鍵字" -n 3 -d --status      # 狀態
./hongguo-list -q "關鍵字" -n 3 -d --pause       # 暫停
./hongguo-list -q "關鍵字" -n 3 -d --resume      # 恢復
./hongguo-list -q "關鍵字" -n 3 -d --clear-queued # 清空等待
./hongguo-list -q "關鍵字" -n 3 -d --clear-all   # 清空未完成
./hongguo-list -q "關鍵字" -n 3 --remove 1,3,5-10 # 刪除特定集數
```

### 完整參數說明

| 參數 | 簡寫 | 說明 | 預設值 |
|------|------|------|--------|
| `-q` | | 搜尋關鍵字 (必填) | - |
| `-n` | | 選擇第幾個搜尋結果 | 1 |
| `-d` | | 背景下載模式 | false |
| `-o` | | 下載輸出目錄 | `~/Projects/videoapp/downloads` |
| `-all` | | 僅顯示搜尋結果 | false |
| `--status` | | 顯示下載狀態並退出 | - |
| `--pause` | | 暫停所有下載 | - |
| `--resume` | | 恢復所有暫停/失敗的下載 | - |
| `--clear-queued` | | 清空所有等待中的下載 | - |
| `--clear-all` | | 清空所有未完成的下載任務 | - |
| `--remove` | | 刪除特定集數 (格式: 1,3,5-10) | - |
| `-h` | | 顯示說明 | - |

## 測試驗證結果

- ✅ 搜尋 "反派親媽" 返回 14 個結果
- ✅ 選擇第 3 個 → 196 集全部加入佇列
- ✅ 自動恢復暫停任務
- ✅ `--status` 顯示：總計、下載中、等待中、已完成、失敗
- ✅ `--pause` 暫停所有下載
- ✅ `--resume` 恢復所有暫停/失敗任務 (恢復 369 個任務)
- ✅ `--clear-queued` 清空等待中下載
- ✅ `--clear-all` 清空所有未完成任務
- ✅ `--remove 1,3,5-7` 刪除特定集數 (支援範圍)
- ✅ `--status` 顯示摘要統計 + 當前下載進度條/速度 + 等待佇列前 5 個預覽

## 關鍵技術實現

1. **不預先解析 URL** - 加入佇列時只存章節資訊，videoapp 下載器在**每集下載前即時解析**，避免簽名過期
2. **批次加入** - 使用 `Entries` 單次最多 500 集
3. **自動恢復** - 加入佇列後自動 `resume` 暫停/失敗任務
4. **即時進度** - 每 2 秒輪詢 `DownloadSnapshot()`，顯示摘要統計 + 當前下載進度條/速度 + 等待佇列前 5 個預覽
5. **任務持久化** - `index.json` 持久化儲存，重啟後自動恢復 queued/downloading/paused 任務
6. **管理指令** - 支援 pause/resume/clear-queued/clear-all/remove 完整生命週期管理
7. **零修改現有代碼** - 只新增導出類型/方法，不改動任何現有邏輯

## 源碼位置

- **CLI 入口**: `./native/cmd/hongguo-list/main.go`
- **Core 修改**: `./native/core/app_runtime.go` (導出類型和方法)
- **類型導出**: `./native/core/app_downloads.go` (NativeDownloadJob, NativeDownloadEpisode)

## 專案已完整交付可用

 編譯方式

 ### 方法 1：直接編譯（推薦）

 ```bash
cd ./native
go build -o ../hongguo-list ./cmd/hongguo-list
 ```

 ### 方法 2：從專案根目錄編譯

 ```bash
cd /Users/david/Projects/videoapp
go build -o hongguo-list ./native/cmd/hongguo-list
 ```

 ### 方法 3：交叉編譯 (Linux/Windows)

 ```bash
# Linux (amd64)
GOOS=linux GOARCH=amd64 go build -o hongguo-list-linux ./cmd/hongguo-list

# Windows (amd64)
GOOS=windows GOARCH=amd64 go build -o hongguo-list.exe ./cmd/hongguo-list
 ```

 ### 前置需求

 ```bash
# 確保 Go 版本 >= 1.21
go version

# 模組已在 ./native/go.mod 定義
cd ./native
go mod tidy  # 首次編譯前執行
 ```

 ### 依賴模組

 - github.com/bogdanfinn/fhttp - HTTP client
 - github.com/bogdanfinn/tls-client - TLS client
 - github.com/dop251/goja - JS 引擎
 - golang.org/x/net, golang.org/x/sys, golang.org/x/text, golang.org/x/crypto

 ### 依賴 hongguo 模組

 編譯前需確保模組已安裝：

 ```
./data/modules/hongguo/
├── main.js
└── manifest.json
 ```

 (從 https://github.com/gentoobreaking/video-src/hongguo 複製而來)

