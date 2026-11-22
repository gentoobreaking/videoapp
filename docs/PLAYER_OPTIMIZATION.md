# videoapp 播放器優化與畫質最佳化建議

> 本文件記錄播放器（Flutter + media_kit / libvlc）的優化及畫質最佳化方案，供開發參考與追蹤實作進度。  
> 對應關鍵檔案：`lib/ui/player/playback_handle.dart`、`lib/ui/player/player_video.dart`、`lib/playback_session.dart`、`lib/playback_preferences.dart`

---

## 1. 現狀摘要

播放器已具備的基礎優化：

- Android `mediacodec-copy`、iOS/Mac `videotoolbox-copy`、Windows `d3d11va-copy` 硬體解碼
- Android 解碼加速：`vd-lavc-skiploopfilter=nonkey`、`threads=4`、`fast=yes`、`framedrop=vo`、`video-sync=audio`
- 快取上限：一般 32MB，受限時 4MB；`network-timeout: 20`
- 下一集預載（standby）、畫質選單（720P+）、倍速、畫面比例（VideoFit）
- 視窗輸出尺寸 debounce：300ms

---

## 2. 播放器啟動與流暢度（Dart 層）

### 2.1 調整 PlayerConfiguration（立即可做）

檔案：`lib/ui/player/playback_handle.dart`

```dart
Player _player() => Player(
  configuration: const PlayerConfiguration(
    bufferSize: 64 * 1024 * 1024,   // 32MB → 64MB，降低啟動緩衝斷續
    logLevel: MPVLogLevel.warn,     // error 太嚴重，warn 方便排查
  ),
);
```

### 2.2 降低輸出尺寸 debounce（立即可做）

檔案：`lib/ui/player/player_video.dart`，`_VideoOutput._schedule`

目前固定 300ms，切換全螢幕或視窗縮放時畫面會有可感知延遲。建議縮短：

```dart
static const _outputSizeDebounce = Duration(milliseconds: 100);
// ...
_timer = Timer(_outputSizeDebounce, _apply);
```

注意：不要過短（例如 0ms 或 10ms），否則參數尚未穩定時會頻繁呼叫原生 `setSize`，反而可能導致畫面抖動。100～200ms 是較平衡的區間。

### 2.3 避免重複建立 Player（後續優化）

檔案：`lib/ui/player/playback_handle.dart`

目前 `PlaybackHandle` 每次建立 `main` + `standby` 兩個 `Player`。切集時可優先複用已建立的 Player，只重新 `open()` 新媒體，減少原生資源建立與銷毀開銷。

---

## 3. mpv / 原生層優化（`playback_session._configure`）

檔案：`lib/playback_session.dart`

在現有 `_configure()` 後續補入下列 mpv 屬性，提升網路串流穩定性與解碼效率：

```dart
// 網路快取與逾時
await platform.setProperty('cache', '102400');           // 100 MB 網路快取
await platform.setProperty('network-timeout', '30');     // 20 → 30 秒

// 解碼效率（多核自動選執行緒數）
await platform.setProperty('vd-lavc-threads', '0');      // 0 = 自動，多核機器更快
await platform.setProperty('vd-lavc-fast', 'yes');       // 已有
await platform.setProperty('framedrop', 'vo');           // 已有，掉幀優先保音畫同步
await platform.setProperty('video-sync', 'audio');       # 已有 Android，可擴充至其他平台

// 畫質與色彩
await platform.setProperty('colormatrix', 'auto');       // 色彩空間自動
await platform.setProperty('tonemapping', 'generic');    // HDR 色調映射，避免 HDR 內容發灰/過亮
await platform.setProperty('scale', 'spline36');         // 放大濾鏡（畫質優於 bilinear）
await platform.setProperty('cscale', 'spline36');        // 色彩通道縮放
await platform.setProperty('dscale', 'mitchell');        // 顯示縮放
await platform.setProperty('deinterlace', 'yes');        // 內建隔行處理（舊源適用）

// 動態快取（視互動狀態調整，見 5.4）
await platform.setProperty('demuxer-max-bytes', '...');
```

---

## 4. 畫質最佳化建議

### 4.1 硬體解碼策略（P1）

目前全用 `...-copy`（解碼後再拷回記憶體），穩定但損效能與色彩精度。在支援平台時，可改用不加 `-copy` 的硬體解碼（如 `d3d11va`、`videotoolbox`、`auto`），降低 CPU 負載與色彩轉換損耗。

### 4.2 畫質選單擴充（P1）

檔案：`lib/playback_session.dart` `qualities`、`lib/ui/player/player_surface.dart` `_popupBody`

- 僅列出 720P 以上，建議加入 1080P / 4K 選項，並新增「原始碼率」選項。
- 「自動」模式可根據實際網速（`cache-speed`）動態降階，避免高頻緩衝。

### 4.3 像素比與邊框（P2）

檔案：`lib/ui/player/player_video.dart`

- 高 DPI 裝置確保 `setSize` 不低於實際裝置像素，避免畫面模糊。
- `VideoFit.auto` 預設 letterbox，可在偏好新增「智慧裁切」以避免黑邊。

### 4.4 色彩與 HDR（P1）

補入原生層：
- `colormatrix`、`tonemapping`、`colormatrix-input-range`
- 讓 HDR/SDR 內容色彩正確，避免發灰或過亮。

### 4.5 銳化 / 降噪（P2）

視效能而定，補入：
- `sharpen`、`denoise`
- 改善低畫質來源觀感。

---

## 5. 預載與換集體驗（`playback_session`）

檔案：`lib/playback_session.dart`

### 5.1 預載數量（P1）

`preloadCount` 預設 1，建議提升至 2–3，並視實際網路速度自動調整。

### 5.2 Standby 預載更多集（P2）

`preopen` 預設非電視開啟，可預載更多集以縮短換集白屏時間。

### 5.3 動態快取上限（P1）

`_limitCache` 在非互動時限為 4MB，播放中可動態放寬至 32MB，避免跳段時重新緩衝。

---

## 6. 實作優先級

| 優先級 | 項目 | 說明 |
|--------|------|------|
| **P0** | `PlayerConfiguration.bufferSize` 調大、`logLevel` 改 `warn` | `playback_handle.dart` |
| **P0** | 輸出尺寸 debounce 300ms → 100ms | `player_video.dart` |
| **P0** | `_configure` 補 `cache`、`network-timeout`、`vd-lavc-threads` 等 | `playback_session.dart` |
| **P1** | 畫質選單加入 1080P / 4K 與原始碼率 | `playback_session.dart`、`player_surface.dart` |
| **P1** | 非 `-copy` 硬體解碼選項 | `playback_session.dart` |
| **P1** | `colormatrix`、`tonemapping` 色彩修正 | `playback_session.dart` |
| **P1** | 動態預載數量、動態快取上限 | `playback_session.dart` |
| **P2** | 高 DPI 輸出尺寸、`sharpen` / `denoise`、智慧裁切 | `player_video.dart`、`playback_session.dart` |
| **P2** | 切集複用 Player、Standby 預載更多集 | `playback_handle.dart`、`playback_session.dart` |

---

## 7. 發布提醒

依專案 `CLAUDE.md` 規範，若修改後發布新版，請：

1. 同步遞增 `pubspec.yaml` 的版本號與構建號。
2. 在 `CHANGELOG.md` 加入完整版本標題（如 `## 0.2.72+79`）。
3. 每個版本的更新日誌不得超過 3500 字，且只需簡單描述，不新增解釋性註解。
4. 未驗證的改動標為開發快照，提醒用戶在對應平台進行實機測試，驗證通過後移除標記。
