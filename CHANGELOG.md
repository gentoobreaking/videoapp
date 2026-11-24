# 更新日志

每个版本一节，标题为 `pubspec.yaml` 中的完整版本号。发布工作流会把对应一节写入 GitHub Release 说明。

## 2.0.9+141

### 更新内容

- 電視模式播放進度條支援滑鼠/觸控板拖拉，即時預覽目標時間
- 新增快轉/快退步長設定（設定 → 播放 → 進階）：
  - 自動模式：根據影片長度動態調整（≤10分 10秒、10-30分 30秒、30-60分 1分、1-2小時 2分、2-4小時 5分、>4小時 10分）
  - 自訂模式：固定步長可選 5秒/10秒/15秒/30秒/1分/2分/5分/10分
- 長按方向鍵/快轉鍵加速：連按 300ms 內遞增 1.5x，上限 8x
- 封面下載/解碼錯誤日誌增強（CoverImage errorBuilder、Go diagnosticEvent、記憶體監測）

## 2.0.8+140

### 更新内容

- 修復 Android 更新安裝失敗：APK 改為寫入 App cache 並由 FileProvider 提供安裝，不再出現「找不到配置的根目錄」錯誤（开发快照，需在 Android 实机测试）
- 更新包同時複製到公開 Download 資料夾，自動安裝失敗時可手動安裝；下載前先行詢問儲存權限
- 啟動時自動清理 App 快取與歷史殘留更新檔，Download 僅保留最新一份，避免重複更新堆積佔用空間

## 2.0.7+138

### 更新内容

- 驗證「更新下載」修復：checkUpdate 依設備 ABI 從 release assets 挑選正確 APK 下載網址，按下「更新」應能正確下載並進入安裝畫面（开发快照，需在对应平台实机测试）
- 下載後驗證 APK 內容，非 APK 時明確提示

## 2.0.6+138

### 更新内容

- 驗證「更新下載」修復：checkUpdate 依設備 ABI 從 release assets 挑選正確 APK 下載網址，按下「更新」應能正確下載並進入安裝畫面（开发快照，需在对应平台实机测试）
- 下載後驗證 APK 內容，非 APK 時明確提示

## 2.0.6+137

### 更新内容

- 修復按下「更新」下載失敗：checkUpdate 依設備 ABI（arm64-v8a/armeabi-v7a/x86_64）從 release assets 挑選正確 APK 下載網址，不再誤抓 Release 頁面（开发快照，需在对应平台实机测试）
- 下載後驗證 APK 內容，非 APK 時明確提示，不再把 HTML 當安裝包

## 2.0.5+136

### 更新内容

- 修復版本比對邏輯：從 GitHub release tag（app-vX.Y.Z-N-android 格式）正確提取語義版本，同版本不再誤報「發現新版本」（开发快照，需在对应平台实机测试）
- 修復舊備份匯入時 bufferSize/cacheSize 預設值為 8 MB，不再遺失

## 2.0.4+135

### 更新内容

- 修復 Android CI 編譯失敗：FileProvider 缺失導入
- 修復版本比對 bug：正確提取語義版本 (X.Y.Z) 進行比對，避免同版本誤判
- About 畫面顯示完整版本號碼 (含 build number)
- 播放器緩衝/快取預設值改為 8 MB
- 修復舊備份匯入時 bufferSize/cacheSize 為 null 的問題

## 2.0.2+133

### 更新内容

- 播放器偏好變更時自動重新播放並套用新參數，修復離開播放頁後再進入不生效的問題（开发快照，需在对应平台实机测试）
- 检查更新时按下「更新」按钮，改为 App 自己下載 APK 並安裝（開發快照，需在實機測試）

## 2.0.2+132

### 更新内容

- 播放器移除 tonemapping、highQualityScaling、deinterlace 三個 mpv 原生屬性，簡化播放器設定介面（开发快照，需在对应平台实机测试）

## 2.0.2+131

### 更新内容

- 播放器偏好變更時自動重新播放並套用新參數，無須手動換集或重開應用（开发快照，需在对应平台实机测试）
- 播放器換集時自動重新套用硬體解碼、快取、縮放濾鏡、銳化降噪等 mpv 屬性（开发快照，需在对应平台实机测试）

## 2.0.2+130

### 更新内容

- 播放器進階設定重構：cacheSize 支援「關閉」選項（使用 mpv 內建預設快取），總開關 enableMpvAdvanced 獨立控制其餘 mpv 原生屬性套用（开发快照，需在对应平台实机测试）

## 2.0.2+129

### 更新内容

- 電視端備份導出不再彈出系統「儲存檔案」選單，直接將備份寫入下載目錄，檔名為 `videoapp-backup-YYYY-MM-DD.json`（开发快照，需在对应平台实机测试）
- 非電視平台備份導出仍保留使用者自行選擇儲存位置（开发快照，需在对应平台实机测试）

## 2.0.2+128

### 更新内容

- 播放器 mpv 原生屬性全部改為獨立開關，預設全關閉：cache、network-timeout、vd-lavc-threads、colormatrix、tonemapping、scale/cscale/dscale、deinterlace、sharpen/denoise（开发快照，需在对应平台实机测试）
- network-timeout 預設值從 30 秒改回 20 秒，cache 預設不再設定（走原本 demuxer-max-bytes 邏輯）（开发快照，需在对应平台实机测试）
- 設定介面 › 播放器進階 新增每個 mpv 屬性的「啟用」開關，可逐一開啟測試，找出導致電視黑畫面的屬性（开发快照，需在对应平台实机测试）

## 2.0.2+127

### 更新内容

- GitHub 版本檢查 Token 編譯時常數由 `GITHUB_TOKEN` 更名為 `VIDEOAPP_RELEASE_TOKEN`，與 `video-src` 獨立，終端用戶不需要輸入（开发快照，需在对应平台实机测试）

## 2.0.2+126

### 更新内容

- 版本檢查改用 GitHub REST API（`/repos/gentoobreaking/videoapp/releases/latest`），不再依賴原生 Go 層，Token 從 CI/CD Secrets 註入作為編譯時常數（`VIDEOAPP_RELEASE_TOKEN`），與 `video-src` 獨立，終端用戶不需要輸入（开发快照，需在对应平台实机测试）
- 播放器緩衝大小 bufferSize、網路快取大小 cacheSize、網路超時時間 networkTimeout、解碼執行緒數 decoderThreads、色彩空間 colormatrix、HDR 色調映射 tonemapping、高品質縮放濾鏡 highQualityScaling、隔行處理 deinterlace、銳化與降噪 sharpenDenoise、輸出尺寸 debounce outputSizeDebounce 全部改為可在設定介面調整，不再硬編碼（开发快照，需在对应平台实机测试）
- 設定介面新增「播放器進階」區塊，包含上述所有播放器進階參數（开发快照，需在对应平台实机测試）

## 2.0.2+125

### 更新内容

- 恢复预加载集数 preloadCount 预设值为 1，交由用户在设置介面调整（开发快照，需在对应平台实机测试）
- 新增播放偏好 conservativeMode（電視端保守模式），开启后降低记忆体与运算负载，适用于较舊的电视或机顶盒（开发快照，需在对应平台实机测试）
- 播放器依据保守模式自动调整缓存、色调映射、缩放滤镜、锐化与降噪等参数（开发快照，需在对应平台实机测试）
- 设定介面新增「電視端保守模式」开关，仅在电视平台显示（开发快照，需在对应平台实机测试）

## 2.0.2+124

### 更新内容

- 播放器 Player bufferSize 32MB 增至 64MB，logLevel 由 error 改为 warn（开发快照，需在对应平台实机测试）
- 视频输出尺寸 debounce 由 300ms 缩短至 100ms，降低全屏/窗口切换时画面错位延迟（开发快照，需在对应平台实机测试）
- 播放器 _configure 补充 mpv cache、网络超时、解码线程、色彩空间与缩放滤镜属性（开发快照，需在对应平台实机测试）
- 默认预载数量 preloadCount 由 1 增至 2，缩短换集等待时间（开发快照，需在对应平台实机测试）
- 硬件解码选取零拷贝解码器（Android mediacodec、iOS/Mac videotoolbox、Windows d3d11va），保留 optimized 为 -copy 行为（开发快照，需在对应平台实机测试）
- 播放器新增 sharpen 与 denoise mpv 属性，改善低画质来源观感（开发快照，需在对应平台实机测试）

## 2.0.2+123

### 更新内容

- app_device.dart 的 catch (_) 改为记录到 DiaryService，避免静默吞掉错误
- 新增 Dependabot、CodeQL 和 gosec 安全扫描（GitHub Actions）
- Go 核心模组治理上限：jsProvider.Close() 在卸载时释放 goja VM；Unregister 自动调用 Close；quickCall 接受 context.Context 并尊重取消；模组返回 JSON 增加 16 MB 大小上限（开发快照，需在客户端实测模组卸载、请求取消与超大 JSON 响应）
- CI GitHub Actions 全部锁定到具体 commit SHA，避免上游 action 意外变更
- Android 发布改为手动触发，不再随 Checks 自动出包
- Worker 接收端 repository 改为 gentoobreaking/guoapp；/v1/ping 新增 IP 限流与可选 Bearer 鉴权；scheduled() 加入 try/catch；wrangler.toml 移除硬编码 database_id（开发快照，需在 Worker 部署后实测限流与鉴权）
- 首页发现页新增站源模组更新提示横幅，仅管理员可见，点击跳转至模组页（开发快照，需以管理员账号在客户端打开界面实测）
- AppRepository 移除所有 no-op/throw 預設實作，僅留抽象簽名；預設行為移至 FakeRepository，避免「忘記實作」在執行期才拋例外
- 平台判斷集中到 platform_capabilities.dart，遷移 app_scope.dart、app_device.dart、picture_in_picture.dart，避免 Platform.isX 散落各處
- 補 native/core network_limiter 與 catalog_cache 單元測試（限流、回退、間隔、context 取消、合併去重、遷移、通用分類等）

## 2.0.3+134

### 更新内容

- 修復 Android App 中 `FileProvider` 缺失導入問題，支援 release APK 编译
- 修復版本比對 bug：`currentAppVersion()` 返回 `"2.0.3+134"` 時，不再誤判為有更新
- About 畫面新增顯示完整版本號碼：`2.0.3+134`（含 build number）
