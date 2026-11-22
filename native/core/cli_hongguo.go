//go:build ignore
// +build ignore

package core

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func HongguoListCLI() {
	keyword := flag.String("q", "", "搜尋關鍵字")
	choice := flag.Int("n", 1, "選擇第幾個搜尋結果 (預設 1)")
	all := flag.Bool("all", false, "列出所有搜尋結果不下載")
	help := flag.Bool("h", false, "顯示說明")
	flag.Parse()

	if *help || *keyword == "" {
		fmt.Fprintln(os.Stderr, "用法: hongguo-list -q \"關鍵字\" [-n 選項編號] [-all]")
		fmt.Fprintln(os.Stderr, "範例: hongguo-list -q \"成家徒四壁\" -n 2")
		fmt.Fprintln(os.Stderr, "範例: hongguo-list -q \"成家徒四壁\" -all")
		os.Exit(1)
	}

	// 建立臨時目錄給 nativeEngine 使用
	tmpDir, err := os.MkdirTemp("", "hongguo-cli-*")
	if err != nil {
		fmt.Fprintf(os.Stderr, "建立暫存目錄失敗: %v\n", err)
		os.Exit(1)
	}
	defer os.RemoveAll(tmpDir)

	dataDir := filepath.Join(tmpDir, "data")
	cacheDir := filepath.Join(tmpDir, "cache")
	downloadsDir := filepath.Join(tmpDir, "downloads")

	// 初始化 nativeEngine (載入模組)
	engine, err := NewNativeEngine(dataDir, cacheDir, downloadsDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "初始化引擎失敗: %v\n", err)
		os.Exit(1)
	}

	// 取得 hongguo provider
	downloader := engine.downloader
	provider, ok := downloader.provider("hongguo")
	if !ok {
		fmt.Fprintf(os.Stderr, "找不到 hongguo 模組，請確認模組已安裝\n")
		os.Exit(1)
	}

	// 取得 Searcher 介面
	searcher, ok := providerAs[Searcher](provider)
	if !ok {
		fmt.Fprintf(os.Stderr, "hongguo 模組不支援搜尋\n")
		os.Exit(1)
	}

	ctx := context.Background()

	// 搜尋
	fmt.Printf("搜索關鍵字：%s\n", *keyword)
	items, hasMore, err := searcher.Search(ctx, 1, *keyword)
	_ = hasMore
	if err != nil {
		fmt.Fprintf(os.Stderr, "搜尋失敗: %v\n", err)
		os.Exit(1)
	}

	if len(items) == 0 {
		fmt.Println("未搜索到任何劇集。")
		os.Exit(0)
	}

	fmt.Println("\n搜尋結果：")
	for i, item := range items {
		fmt.Printf("  %d. [%s] %s\n", i+1, item.SourceID, item.Title)
	}

	if *all {
		os.Exit(0)
	}

	// 選擇劇集
	idx := *choice - 1
	if idx < 0 || idx >= len(items) {
		fmt.Fprintf(os.Stderr, "編號無效（範圍 1-%d），已自動選擇第 1 個。\n", len(items))
		idx = 0
	}

	selected := items[idx]
	fmt.Printf("\n已選擇：[%d] [%s] %s\n", idx+1, selected.SourceID, selected.Title)

	// 取得詳情
	fmt.Printf("\n正在獲取分集列表...\n")
	drama, chapters, err := provider.Detail(ctx, selected.SourceID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "取得詳情失敗: %v\n", err)
		os.Exit(1)
	}

	if len(chapters) == 0 {
		fmt.Println("未找到分集。")
		os.Exit(0)
	}

	fmt.Printf("共 %d 集數，正在逐集取得播放地址...\n\n", len(chapters))
	fmt.Printf("%-6s %-22s %s\n", "集數", "影片 ID", "MP4 下載網址")
	fmt.Println(strings.Repeat("-", 120))

	urlFile := fmt.Sprintf("hongguo_%s_urls.txt", selected.SourceID)
	f, err := os.Create(urlFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "建立輸出檔案失敗: %v\n", err)
		os.Exit(1)
	}
	defer f.Close()

	success := 0
	fail := 0

	for i, ch := range chapters {
		videoID := extractVideoID(ch)
		
		task := Task{
			DramaID: drama.ID,
			Chapter: ch,
			Index:   i + 1,
		}

		media, err := provider.ResolveMedia(ctx, task)
		if err != nil {
			fail++
			fmt.Printf("%-6d %-22s [獲取失敗: %v]\n", i+1, videoID, err)
			break
		}

		success++
		fmt.Fprintln(f, media.URL)
		fmt.Printf("%-6d %-22s %s\n", i+1, videoID, media.URL)
	}

	fmt.Println(strings.Repeat("-", 120))
	if fail > 0 {
		fmt.Printf("中斷：成功 %d 集，第 %d 集開始獲取失敗，已停止。\n", success, success+1)
	} else {
		fmt.Printf("完成：成功 %d 集，失敗 %d 集。\n", success, fail)
	}
	fmt.Printf("所有可用的 MP4 網址已儲存至：%s\n", urlFile)
	fmt.Printf("若需批量下載，可使用：wget -i %s\n", urlFile)
}

func extractVideoID(ch Chapter) string {
	// Chapter.ID 通常是 video_id 或包含 video_id
	key := ch.ID
	if strings.HasPrefix(key, "hongguo:") {
		parts := strings.Split(key, ":")
		if len(parts) >= 3 {
			return parts[2]
		}
	}
	return key
}