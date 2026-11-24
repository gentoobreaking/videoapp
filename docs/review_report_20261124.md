基於兩份審查報告（2026-11-18、2026-11-20）與目前版本 `2.0.9+143`，以下是**目前實作的改善空間總結**：

---

## ✅ 已完成的關鍵項（P0/P1 多數已修復）

| 項目 | 狀態 |
|------|------|
| CI `pull_request` 觸發器 + 阻斷 | ✅ `checks.yml` 已有 |
| FFI `recover()` 防線 | ✅ `guardBackground` + 7 處入口 |
| SSRF `allowedAddress` 下沉 | ✅ 媒體出口攔截 + 重定向檢查 |
| `rememberDramaQuality` debounce | ✅ 400ms 合併寫檔 |
| `LocalStore` 部分拆分 | ✅ `StoreSection` 細分通知器 |
| 非同步 job（`moveDownloads`/`deleteAllData`） | ✅ `app_data_job.go` |
| `packages/PATCHES.md` | ✅ 三個 fork 考證完成 |
| `.fvmrc` 釘死 Flutter 3.47.9 | ✅ |
| README 設定組數修正 (8→9) | ✅ |
| goja VM 卸載釋放、`quickCall` 尊重取消、JSON 上限 | ✅ |
| `AppRepository` no-op 移至 `FakeRepository` | ✅ |
| 平台判斷集中 `platform_capabilities.dart` | ✅ |
| Worker 安全性修復 | ✅ |

---

## ⚠️ 仍待處理的高優先級項（P0/P1/P2）

### 1. **Go 核心全局鎖內 I/O**（P0-3，風險中高）
```go
// 仍在鎖內做 I/O 的位置：
- app_catalog_cache.go: writeCatalogDiskLocked 寫 32MB JSON 持鎖
- app_downloads.go: 下載進度每秒重寫索引持鎖
- network_browser.go: 每請求開診斷檔案
- app_stream_cenc.go: CENC 解密持 cencMu 跑 64 次順序 HTTP
```
> **影響**：阻塞所有原生呼叫，播放/下載介面有卡頓風險。

### 2. **測試覆蓋缺口**（P2-1/2-2）
| 區域 | 覆蓋率 | 狀態 |
|------|--------|------|
| `native/bridge` (C ABI) | 0% | ❌ 關鍵：malloc/free、panic 恢復、垃圾輸入 |
| `network_dns.go` / `network_cdn.go` | 0% | ❌ |
| `portable_data` / `background_downloads` / `cover_decoder` | 0% | ❌ |
| `cmd/moduletool` | 0% | ❌ |

### 3. **模組安裝鏈安全**（P2-3）
- 僅允許 `https://`（現接受 `http://`）
- 商店索引簽名驗證
- `Folder` 路徑 traversal 檢查
- `deleteAllData` 目錄歸屬檢查

### 4. **Go 核心其他問題**（P2-4）
- `provider_host.go:266` direct client **無 Timeout**
- `http.Client` 4 處按值複製
- CDN/瀏覽器快取淘汰 = 隨機刪一筆 map
- DoH 繞過限流器、DNS 快取無上限
- 硬寫 AES key/IV、XOR key (`app_covers.go`)
- LAN 串流 server 綁所有介面無鑑權
- 錯誤脫屑保留帶簽名的媒體網址

### 5. **Android/iOS 建置細節**（P3-3）
- Release 未開 minify/shrink（三 ABI 包體大）
- `namespace` 與 `applicationId` 不同步
- `GeneratedPluginRegistrant` 正則 hack 移除 `integration_test`
- `MainActivity.kt` 770 行單一 Activity

---

## 🎨 架構層面改善建議（中長期）

### 1. **Dart 分層不足**（P1-1）
- `detail_page.dart` 1737 行、`television_player_page.dart` 1460 行
- UI 直接 import `local_store.dart` (220 處) + `core_bridge.dart` (62 處)
- **建議**：仿 `drama_feed`/`follow_state`，每頁抽 `*_feed.dart` / `*_state.dart`，頁面只留 build

### 2. **狀態管理模式統一**
- 播放器模式正確：`PlaybackSession` 不為 position 發通知，`PlayerSurface` 只在控制列可見時 `setState`
- `LocalStore` 仍為單一粗粒度 Notifier，建議繼續拆分：
  - `FavoritesNotifier` / `HistoryNotifier` / `SettingsNotifier` / `UsersNotifier` / `QualityFilterNotifier`

### 3. **依賴管理**
- 三個 `dependency_overrides` 本地 fork：定期檢查上游同步，或改為 upstream patch
- `media_kit_video` fork 整包 796KB，維護成本高

---

## 📊 當前專案健康度評分

| 維度 | 分數 | 備註 |
|------|------|------|
| **建置/ CI** | 9/10 | PR 阻斷、格式/分析/測試全綠 |
| **安全性** | 8/10 | SSRF 堵住、FFI recover、Worker 安全；剩硬寫金鑰、LAN 串流 |
| **Go 核心品質** | 6/10 | 全局鎖 I/O、Timeout 缺失、快取策略、測試覆蓋低 |
| **Dart 架構** | 6/10 | 上帝檔、分層不足、粗粒度 Notifier |
| **測試覆蓋** | 5/10 | bridge 0%、核心模組多為 0%、Dart 邏輯層缺測 |
| **文件/維護** | 8/10 | PATCHES.md、README 同步、CHANGELOG 規範 |
| **跨平台建置** | 7/10 | Android minify 缺失、iOS ATS 說明缺失 |

---

## 🚀 建議下一步動工順序

| 優先級 | 項目 | 預估成本 | 理由 |
|--------|------|----------|------|
| **P0** | Go 全局鎖 I/O 移出 | 中 | 直接影響播放/下載流暢度 |
| **P0** | `native/bridge` 測試 | 小 | C ABI 是單點故障，panic 即閃退 |
| **P1** | 模組安裝鏈安全 | 中 | 供應鏈攻擊面 |
| **P1** | 補核心模組測試 (DNS/CDN/下載/catalog/stream) | 中 | 回歸底線 |
| **P2** | Go 核心其他問題 (Timeout、Client 複製、快取、硬寫金鑰) | 中 | 穩定性與安全 |
| **P2** | Dart 分層重構 (`*_feed`/`*_state`) | 大 | 長期維護性 |
| **P3** | Android release minify、namespace 同步 | 小 | 包體積、建置穩定 |
| **P3** | 定期同步三個 fork 上游 | 持續 | 維護債控制 |

---

## `dependency_overrides` 是什麼？

Flutter/Dart 專案中，**強制使用本地目錄版本替換上游套件**的機制。

```yaml
dependency_overrides:
  media_kit_libs_windows_video:
    path: packages/media_kit_libs_windows_video
  media_kit_video:
    path: packages/media_kit_video
  shared_preferences_windows:
    path: packages/shared_preferences_windows
```

---

## 這三個包分別是什麼？

| 包 | 上游來源 | 本地版本 | 修改原因 |
|----|----------|----------|----------|
| **media_kit_video** | `media-kit/media-kit` | `2.0.1+duanju.1` | **Windows 關閉播放器前同步釋放渲染上下文**，修復退出播放頁幾秒後閃退（#116） |
| **media_kit_libs_windows_video** | 同上 | `1.0.11+duanju.1` | **Windows libmpv/ANGLE 改從自建 release 下載**，上游構建版本已刪除 |
| **shared_preferences_windows** | `flutter/packages` | `2.4.1` | **Windows 設定檔原子寫入**（先寫臨時檔再替換、保留上一版），修復斷電後 `FormatException` |

---

## 為什麼要這樣做？

| 原因 | 說明 |
|------|------|
| **上游未合併修復** | 這些修復是針對本專案的具體崩潰/構建問題，PR 到上游需時間審核 |
| **上游構建依賴消失** | `media_kit_libs_windows_video` 依賴的 mpv-winbuild-cmake 版本已被上游刪除，必須自建 |
| **Windows 平台特有** | 這三個問題只在 Windows 發生，其他平台用上游版本即可 |

---

## 維護成本與風險

| 風險 | 影響 |
|------|------|
| **手動同步上游** | 上游釋出新版時，需手動 `diff`、重新套用補丁、升版本號（`+duanju.N`） |
| **整包 vendored** | `media_kit_video` 整包 796KB、31 檔，非精準 patch，升級困難 |
| **缺乏自動化** | 無 Dependabot 偵測、無 CI 檢查補丁是否仍適用 |

---

## `PATCHES.md` 的作用

專案在 `packages/PATCHES.md` 記錄了：
- 每個包的**上游版本、本地版本、引入 commit、修改原因**
- **升級上游的標準步驟**（diff → 確認改動 → 重新套用 → 測試 → 提交）

> **注意**：`DEVELOPMENT.md` 只列了其中一個包，`PATCHES.md` 才是完整清單。

---

## 建議改善方向

1. **改為 upstream patch 檔案**（而非整包 vendored），如：
   ```
   packages/media_kit_video.patch
   packages/media_kit_libs_windows_video.patch
   packages/shared_preferences_windows.patch
   ```
   升級時用 `git apply` 更可控。

2. **持續追蹤上游 PR/Issue**，盡早合併移除 override。

3. **CI 加入檢查**：定期比對上游版本，提醒需同步。

---

簡單說：**這是為了解決 Windows 平台特有的崩潰/構建問題，暫時 fork 維護的三個上游套件，待上游合併修復後可移除。**
