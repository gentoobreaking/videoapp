# 红果 站源模組

红果 站源模組，適用於支援 JS 站源的視訊 App。

## 基本資訊

| 欄位 | 值 |
|------|-----|
| 模組 ID | `hongguo` |
| 名稱 | 红果 |
| 版本 | 1.0.8 |
| 執行階段 | JS (goja) |
| 接口版本 | API 1 |
| 成人內容 | 否 |
| 能力 | 搜尋、建議、推薦、彈幕、裝置、榜單、季集、封面、元資料、目錄狀態 |
| 主域 | `hongguoduanju.com` |
| 別名 | `hongguoduanju.com`, `www.hongguoduanju.com` |

## 功能

- **短剧、漫剧、AI 剧、听书分類瀏覽**
- **關鍵字搜尋**
- **彈幕支援**
- **多個榜單**：总热播榜、真人剧榜、漫剧榜、AI剧榜
- **連續摘要（Continuous Feed）**

## 安裝方式

1. 下載本 Release 的 `hongguo-v1.0.8.zip`
2. 在 App 內進入「模組管理」→「安裝包地址」
3. 貼入 zip 下載網址並安裝
4. 安裝完成後，站源列表將出现 `红果`

或直接貼入以下安裝網址：

```
https://github.com/gentoobreaking/video-src/releases/download/hongguo-v1.0.8/hongguo-v1.0.8.zip
```

## 追劇 ID 格式

- 劇集 ID：`hongguo:<sourceId>`
- 分集 ID：`hongguo:<sourceId>:<chapterKey>`

本站源只有一個上游，`manifest.id` 維持為 `hongguo`，追劇 ID 格式發布後不得變更。

## 注意事項

- 這是非成人站源（`adult: false`）。
- 主域為 `hongguoduanju.com`，`www.hongguoduanju.com` 已列入 `aliases`。
- 支援多種進階能力：建議、推薦、彈幕、裝置、榜單、季集、封面修復、元資料、目錄狀態。
- 若站點結構變更導致功能失效，請回報 Issue。
- 發布後 `manifest.id` 與追劇 ID 格式不得更改，否則舊追劇記錄將失效。

## 資源

- `manifest.json`
- `main.js`
