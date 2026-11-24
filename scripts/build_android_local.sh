#!/usr/bin/env bash
# 本地快速構建 armeabi-v7a 版本供實機驗證
# 用法:
#   MODULE_INDEX_TOKEN=xxx ./scripts/build_android_local.sh
#   BUNDLED_MODULES=bundled-modules/hongguo ./scripts/build_android_local.sh
#   MODULE_INDEX_TOKEN=ghp_xxx BUNDLED_MODULES=bundled-modules/hongguo ./scripts/build_android_local.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 自動設置 ANDROID_HOME (macOS 預設位置)
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

echo "🔨 構建 armeabi-v7a release APK (使用 --split-per-abi)..."

# 環境變量
export MODULE_INDEX_TOKEN="${MODULE_INDEX_TOKEN:-}"
export BUNDLED_MODULES="${BUNDLED_MODULES:-}"
if [[ -n "${MODULE_INDEX_TOKEN:-}" ]]; then
    echo "🔑 使用 MODULE_INDEX_TOKEN"
fi

# 1. 先編譯 Go 代碼（嵌入 Token、內建模組）
echo "🔧 編譯 Go 原生代碼..."
BUNDLE_ARGS=()
if [[ -n "${BUNDLED_MODULES:-}" ]]; then
    IFS=',' read -ra MODULES <<< "$BUNDLED_MODULES"
    for m in "${MODULES[@]}"; do
        BUNDLE_ARGS+=(--bundle "$m")
    done
    echo "📦 內建模組: $BUNDLED_MODULES"
else
    echo "📦 未指定內建模組，將僅編譯核心"
fi
python3 scripts/build_native.py --platform android --abi armeabi-v7a "${BUNDLE_ARGS[@]}"

# 2. 確保 Flutter 依賴
flutter pub get

# 3. 構建 APK
flutter build apk --release --split-per-abi --no-tree-shake-icons

APK="build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
if [[ -f "$APK" ]]; then
    SIZE=$(du -h "$APK" | cut -f1)
    # 檢查是否為新構建
    MTIME=$(stat -c %Y "$APK" 2>/dev/null || stat -f %m "$APK")
    NOW=$(date +%s)
    if [[ $((NOW - MTIME)) -lt 120 ]]; then
        echo "✅ 構建完成 (新): $APK ($(du -h "$APK" | cut -f1))"
    else
        echo "⚠️ 檔案較舊，可能未重建: $APK"
    fi
    echo ""
    echo "📱 安裝到連接的裝置:"
    echo "   adb connect <TV_IP>:5555"
    echo "   adb install -r $APK"
    echo ""
    echo "🔍 驗證 ABI (應只含 armeabi-v7a):"
    echo "   unzip -l $APK | grep lib/"
else
    echo "❌ 構建失敗，找不到 $APK"
    ls -la build/app/outputs/flutter-apk/*.apk 2>/dev/null || echo "無"
    exit 1
fi