package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"duanjuapp/native/core"
)

// 定義引擎介面，避免依賴未導出的類型
type Engine interface {
	Downloader() *core.Downloader
	EnqueueDownload(ctx context.Context, input core.NativeInput) (int, error)
	DownloadSnapshot() ([]core.NativeDownloadJob, error)
	ControlDownload(id, action string) error
}

// Web search result structures
type WebSuggestResponse struct {
	SuggestList []WebSuggestItem `json:"suggest_list"`
}

type WebSuggestItem struct {
	DisplayWords []string      `json:"display_words"`
	Keyword      string        `json:"keyword"`
	Name         string        `json:"name"`
	WordType     string        `json:"word_type"`
	VideoData    *WebVideoData `json:"video_data"`
}

type WebVideoData struct {
	CategoryList  []WebCategory `json:"category_list"`
	Celebrities   []any         `json:"celebrities"`
	CreateTime    int64         `json:"create_time"`
	EpisodeCnt    int           `json:"episode_cnt"`
	EpisodeRight  string        `json:"episode_right_text"`
	HotScoreData  WebHotScore   `json:"hot_score_data"`
	PayType       int           `json:"pay_type"`
	SeriesCover   string        `json:"series_cover"`
	SeriesID      json.Number   `json:"series_id"`
	SeriesIntro   string        `json:"series_intro"`
	SeriesStatus  int           `json:"series_status"`
	SeriesTitle   string        `json:"series_title"`
	VIDList       []string      `json:"vid_list"`
}

type WebCategory struct {
	CategoryID int    `json:"category_id"`
	Name       string `json:"name"`
}

type WebHotScore struct {
	Score int64  `json:"score"`
	Text  string `json:"text"`
}

type SearchResult struct {
	SeriesID string
	Title    string
}

func main() {
	keyword := flag.String("q", "", "搜尋關鍵字")
	choice := flag.Int("n", 1, "選擇第幾個搜尋結果 (預設 1)")
	all := flag.Bool("all", false, "列出所有搜尋結果")
	download := flag.Bool("d", false, "直接加入下載佇列 (背景下載，不開介面)")
	output := flag.String("o", "", "下載輸出目錄 (預設: ~/Projects/videoapp/data/downloads)")
	help := flag.Bool("h", false, "顯示說明")
	
	// 管理指令
	status := flag.Bool("status", false, "顯示下載狀態並退出")
	pause := flag.Bool("pause", false, "暫停所有下載")
	resume := flag.Bool("resume", false, "恢復所有暫停的下載")
	clearQueued := flag.Bool("clear-queued", false, "清空所有等待中的下載")
	clearAll := flag.Bool("clear-all", false, "清空所有下載任務")
	remove := flag.String("remove", "", "刪除特定集數 (格式: 1,3,5-10)")

	flag.Parse()

	// 決定下載目錄：-o 指定 > 預設 ~/Projects/videoapp/data/downloads
	homeDir, _ := os.UserHomeDir()
	downloadsDir := filepath.Join(homeDir, "Projects", "videoapp", "data", "downloads")
	if *output != "" {
		downloadsDir, _ = filepath.Abs(*output)
	}
	if err := os.MkdirAll(downloadsDir, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "建立輸出目錄失敗: %v\n", err)
		os.Exit(1)
	}

	// 初始化 videoapp 引擎
	engine, err := core.NewNativeEngine(
		filepath.Join(homeDir, "Projects", "videoapp", "data"),
		filepath.Join(homeDir, "Projects", "videoapp", "data", "cache"),
		downloadsDir,
	)
	if err != nil {
		fmt.Fprintf(os.Stderr, "初始化引擎失敗: %v\n", err)
		os.Exit(1)
	}

	downloader := engine.Downloader()
	provider, ok := downloader.Provider("hongguo")
	if !ok {
		fmt.Fprintf(os.Stderr, "找不到 hongguo 模組，請確認模組已安裝\n")
		os.Exit(1)
	}

	ctx := context.Background()

	// 管理指令
	if *status || *pause || *resume || *clearQueued || *clearAll || *remove != "" {
		if *keyword == "" {
			fmt.Fprintln(os.Stderr, "錯誤：管理指令需要提供 -q 關鍵字")
			os.Exit(1)
		}
		
		// 取得劇集 ID (先搜尋)
		_, err := webSearch(*keyword)
		if err != nil {
			fmt.Fprintf(os.Stderr, "找不到劇集: %s\n", *keyword)
			os.Exit(1)
		}
		
		handleManagement(ctx, engine, downloadsDir, *status, *pause, *resume, *clearQueued, *clearAll, *remove)
		os.Exit(0)
	}

	// 只有 -h 時才顯示說明並退出
	if *help {
		printUsage()
		os.Exit(0)
	}

	// 必須提供關鍵字
	if *keyword == "" {
		fmt.Fprintln(os.Stderr, "錯誤：必須提供搜尋關鍵字 -q")
		printUsage()
		os.Exit(1)
	}

	// 1. Web 搜尋 (使用網頁端 API，無需簽名)
	fmt.Printf("搜索關鍵字：%s\n", *keyword)
	results, err := webSearch(*keyword)
	if err != nil {
		fmt.Fprintf(os.Stderr, "搜尋失敗: %v\n", err)
		os.Exit(1)
	}

	if len(results) == 0 {
		fmt.Println("未搜索到任何劇集。")
		os.Exit(0)
	}

	// 預設行為：只提供關鍵字時，顯示所有結果 (相當於 -all)
	if *choice == 1 && !*all && !*download {
		fmt.Println("\n搜尋結果：")
		for i, item := range results {
			fmt.Printf("  %d. [%s] %s\n", i+1, item.SeriesID, item.Title)
		}
		os.Exit(0)
	}

	fmt.Println("\n搜尋結果：")
	for i, item := range results {
		fmt.Printf("  %d. [%s] %s\n", i+1, item.SeriesID, item.Title)
	}

	// -all 時只顯示結果
	if *all {
		os.Exit(0)
	}

	// 選擇劇集
	idx := *choice - 1
	if idx < 0 || idx >= len(results) {
		fmt.Fprintf(os.Stderr, "編號無效（範圍 1-%d），已自動選擇第 1 個。\n", len(results))
		idx = 0
	}

	selected := results[idx]
	fmt.Printf("\n已選擇：[%d] [%s] %s\n", idx+1, selected.SeriesID, selected.Title)

	// 取得詳情
	fmt.Printf("\n正在獲取分集列表...\n")
	drama, chapters, err := provider.Detail(ctx, selected.SeriesID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "取得詳情失敗: %v\n", err)
		os.Exit(1)
	}

	if len(chapters) == 0 {
		fmt.Println("未找到分集。")
		os.Exit(0)
	}

	fmt.Printf("共 %d 集數\n", len(chapters))

	if *download {
		// 背景下載模式：批次加入 videoapp 下載佇列 (不預先解析 URL)
		// videoapp 下載器會在每集下載前即時 ResolveMedia 取得新鮮簽名 URL
		fmt.Printf("\n加入下載佇列 (%s)...\n", downloadsDir)
		
		// 準備 Entries (支援批次加入，單次最多 500)
		entries := make([]core.NativeDownloadEpisode, len(chapters))
		for i, ch := range chapters {
			entries[i] = core.NativeDownloadEpisode{
				Chapter: ch,
				Index:   i + 1,
			}
		}
		
		jobInput := core.NativeInput{
			Source:    "hongguo",
			Drama:     core.NativeNormalize(drama),
			Entries:   entries,
			Action:    "enqueueDownloads",
			Directory: filepath.Join(homeDir, "Projects", "videoapp", "data"),
			Cache:     filepath.Join(homeDir, "Projects", "videoapp", "data", "cache"),
			Downloads: downloadsDir,
		}
		
		_, err := engine.EnqueueDownload(ctx, jobInput)
		if err != nil {
			fmt.Fprintf(os.Stderr, "加入下載失敗: %v\n", err)
			os.Exit(1)
		}
		
		// 自動恢復下載（新加入的任務可能處於暫停狀態）
		fmt.Printf("\n已加入 %d 集下載佇列，輸出目錄: %s\n", len(chapters), downloadsDir)
		fmt.Println("正在恢復下載...")
		if err := resumeAll(ctx, engine); err != nil {
			fmt.Fprintf(os.Stderr, "恢復下載失敗: %v\n", err)
		}
		
		fmt.Println("下載在背景進行，videoapp 會在每集下載前即時解析簽名 URL")
		
		// 顯示即時下載進度
		watchProgress(ctx, engine, len(chapters))
	} else {
		// 僅列出 URL 模式
		fmt.Printf("\n正在逐集取得播放地址...\n\n")
		fmt.Printf("%-6s %-22s %s\n", "集數", "影片 ID", "MP4 下載網址")
		fmt.Println(strings.Repeat("-", 120))

		urlFile := fmt.Sprintf("hongguo_%s_urls.txt", selected.SeriesID)
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

			task := core.Task{
				DramaID: drama.ID,
				Chapter: ch,
				Index:   i + 1,
			}

			fmt.Printf("%-6d %-22s 正在解析播放地址...\n", i+1, videoID)
			start := time.Now()
			media, err := provider.ResolveMedia(ctx, task)
			elapsed := time.Since(start)
			if err != nil {
				fail++
				fmt.Printf("%-6d %-22s [獲取失敗: %v] (耗時 %v)\n", i+1, videoID, err, elapsed)
				break
			}

			success++
			fmt.Fprintln(f, media.URL)
			fmt.Printf("%-6d %-22s [成功: %v] (耗時 %v)\n", i+1, videoID, media.URL, elapsed)
		}

		fmt.Println(strings.Repeat("-", 120))
		if fail > 0 {
			fmt.Printf("中斷：成功 %d 集，第 %d 集開始獲取失敗，已停止。\n", success, success+1)
		} else {
			fmt.Printf("完成：成功 %d 集，失敗 %d 集。\n", success, fail)
		}
		fmt.Printf("所有可用的 MP4 網址已儲存至：%s\n", urlFile)
		fmt.Println("注意：這些簽名 URL 需要特定 Header/Cookie 才能下載")
		fmt.Println("直接用 wget/curl 下載會得到 403")
		fmt.Println("請用 -d 參數透過 videoapp 下載系統下載")
	}
}

func handleManagement(ctx context.Context, engine Engine, downloadsDir string, status, pause, resume, clearQueued, clearAll bool, remove string) {
	_ = downloadsDir
	
	if *&status {
		snapshot, err := engine.DownloadSnapshot()
		if err != nil {
			fmt.Fprintf(os.Stderr, "獲取狀態失敗: %v\n", err)
			return
		}
		printSnapshot(snapshot)
		return
	}
	
	if pause {
		snapshot, _ := engine.DownloadSnapshot()
		for _, job := range snapshot {
			if job.State == "downloading" || job.State == "queued" {
				engine.ControlDownload(job.ID, "pause")
			}
		}
		fmt.Println("已暫停所有下載")
		return
	}
	
	if resume {
		resumeAll(ctx, engine)
		return
	}
	
	if clearQueued {
		snapshot, _ := engine.DownloadSnapshot()
		for _, job := range snapshot {
			if job.State == "queued" {
				engine.ControlDownload(job.ID, "remove")
			}
		}
		fmt.Println("已清空所有等待中的下載")
		return
	}
	
	if clearAll {
		snapshot, _ := engine.DownloadSnapshot()
		for _, job := range snapshot {
			if job.State != "completed" {
				engine.ControlDownload(job.ID, "remove")
			}
		}
		fmt.Println("已清空所有未完成的下載任務")
		return
	}
	
	if *&remove != "" {
		indices := parseRemoveIndices(remove)
		snapshot, _ := engine.DownloadSnapshot()
		// 建立 index -> jobID 對照
		indexMap := make(map[int]string)
		for _, job := range snapshot {
			indexMap[job.Index] = job.ID
		}
		for _, idx := range indices {
			if jobID, ok := indexMap[idx]; ok {
				engine.ControlDownload(jobID, "remove")
				fmt.Printf("已移除 Ep %d\n", idx)
			}
		}
		return
	}
}

func parseRemoveIndices(s string) []int {
	var result []int
	parts := strings.Split(s, ",")
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if strings.Contains(p, "-") {
			rangeParts := strings.Split(p, "-")
			if len(rangeParts) == 2 {
				start, _ := strconv.Atoi(strings.TrimSpace(rangeParts[0]))
				end, _ := strconv.Atoi(strings.TrimSpace(rangeParts[1]))
				for i := start; i <= end; i++ {
					result = append(result, i)
				}
			}
		} else {
			i, _ := strconv.Atoi(p)
			result = append(result, i)
		}
	}
	return result
}

func resumeAll(ctx context.Context, engine Engine) error {
	snapshot, err := engine.DownloadSnapshot()
	if err != nil {
		return err
	}
	
	resumed := 0
	for _, job := range snapshot {
		if job.State == "paused" || job.State == "failed" {
			if err := engine.ControlDownload(job.ID, "resume"); err != nil {
				fmt.Fprintf(os.Stderr, "恢復任務 %s 失敗: %v\n", job.ID, err)
			} else {
				resumed++
			}
		}
	}
	
	if resumed > 0 {
		fmt.Printf("已恢復 %d 個下載任務\n", resumed)
	}
	return nil
}

func watchProgress(ctx context.Context, engine Engine, expectedCount int) {
	fmt.Println("\n=== 即時下載進度 ===")
	fmt.Println("按 Ctrl+C 停止監控（下載會繼續在背景進行）")
	fmt.Println()
	
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	
	lastProgress := make(map[string]float64)
	
	// 顯示初始狀態
	snapshot, err := engine.DownloadSnapshot()
	if err == nil {
		printSnapshot(snapshot)
	}
	
	for {
		select {
		case <-ctx.Done():
			fmt.Println("\n監控已停止（下載繼續在背景進行）")
			return
		case <-time.After(2 * time.Second):
			snapshot, err := engine.DownloadSnapshot()
			if err != nil {
				fmt.Fprintf(os.Stderr, "\n獲取進度失敗: %v\n", err)
				continue
			}
			
			// 檢查是否有變化
			hasChanges := false
			for _, job := range snapshot {
				if job.Progress != lastProgress[job.ID] {
					hasChanges = true
					lastProgress[job.ID] = job.Progress
				}
			}
			
			if hasChanges {
				// 清除之前的輸出
				fmt.Print("\033[2J\033[H") // 清屏並移至頂部
				fmt.Println("=== 即時下載進度 ===")
				fmt.Println("按 Ctrl+C 停止監控（下載會繼續在背景進行）")
				fmt.Println()
				printSnapshot(snapshot)
			}
			
			// 檢查是否全部完成
			done := 0
			for _, job := range snapshot {
				if job.Progress >= 1.0 {
					done++
				}
			}
			if done >= expectedCount {
				fmt.Printf("\n✅ 所有 %d 集下載完成！\n", done)
				return
			}
		}
	}
}

func printSnapshot(snapshot []core.NativeDownloadJob) {
	// 統計各狀態數量
	var downloading, queued, completed, failed int
	var currentDownloading *core.NativeDownloadJob
	
	for _, job := range snapshot {
		switch job.State {
		case "downloading":
			downloading++
			if currentDownloading == nil || job.Progress > currentDownloading.Progress {
				currentDownloading = &job
			}
		case "queued":
			queued++
		case "completed":
			completed++
		case "failed", "error":
			failed++
		}
	}
	
	// 顯示摘要
	fmt.Printf("📊 總計: %d | 下載中: %d | 等待中: %d | ✅ 已完成: %d | ❌ 失敗: %d\n",
		len(snapshot), downloading, queued, completed, failed)
	fmt.Println()
	
	// 顯示正在下載的任務詳細進度
	if currentDownloading != nil {
		job := currentDownloading
		speed := ""
		if job.Bytes > 0 {
			speed = fmt.Sprintf(" @ %s/s", formatBytes(int64(float64(job.Bytes)/2.0))) // 粗略速度
		}
		fmt.Printf("▶ Ep %d (%s) %s %.1f%% (%s / %s)%s\n",
			job.Index, job.State, progressBar(job.Progress, 40), job.Progress*100,
			formatBytes(job.Bytes), formatBytes(job.Total), speed)
	}
	
	// 顯示等待佇列的前幾個
	if queued > 0 {
		fmt.Printf("⏳ 等待佇列: %d 項 (Ep ", queued)
		count := 0
		for _, job := range snapshot {
			if job.State == "queued" && count < 5 {
				if count > 0 {
					fmt.Print(", ")
				}
				fmt.Printf("%d", job.Index)
				count++
			}
		}
		if queued > 5 {
			fmt.Printf(" ... 等 %d 個", queued)
		}
		fmt.Println(")")
	}
	fmt.Println()
}

func progressBar(progress float64, width int) string {
	filled := int(progress * float64(width))
	if filled > width {
		filled = width
	}
	bar := strings.Repeat("█", filled) + strings.Repeat("░", width-filled)
	return "[" + bar + "]"
}

func formatBytes(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

func printUsage() {
	fmt.Fprintln(os.Stderr, "用法: hongguo-list -q \"關鍵字\" [-n 選項編號] [-all] [-d] [-o 輸出目錄] [管理指令]")
	fmt.Fprintln(os.Stderr, "")
	fmt.Fprintln(os.Stderr, "基本用法:")
	fmt.Fprintln(os.Stderr, "  hongguo-list -q \"關鍵字\"              # 顯示所有搜尋結果")
	fmt.Fprintln(os.Stderr, "  hongguo-list -q \"關鍵字\" -n 3          # 選擇第 3 個")
	fmt.Fprintln(os.Stderr, "  hongguo-list -q \"關鍵字\" -n 3 -d       # 背景下載到 ~/Projects/videoapp/data/downloads")
	fmt.Fprintln(os.Stderr, "  hongguo-list -q \"關鍵字\" -n 3 -d -o ./my_dir  # 指定輸出目錄")
	fmt.Fprintln(os.Stderr, "  hongguo-list -q \"關鍵字\" -all        # 顯示所有搜尋結果")
	fmt.Fprintln(os.Stderr, "")
	fmt.Fprintln(os.Stderr, "下載管理指令 (需配合 -q 指定劇集):")
	fmt.Fprintln(os.Stderr, "  --status         顯示下載狀態並退出")
	fmt.Fprintln(os.Stderr, "  --pause          暫停所有下載")
	fmt.Fprintln(os.Stderr, "  --resume         恢復所有暫停的下載")
	fmt.Fprintln(os.Stderr, "  --clear-queued   清空所有等待中的下載")
	fmt.Fprintln(os.Stderr, "  --clear-all      清空所有未完成的下載任務")
	fmt.Fprintln(os.Stderr, "  --remove 1,3,5-10  刪除特定集數 (支援範圍)")
	fmt.Fprintln(os.Stderr, "")
	fmt.Fprintln(os.Stderr, "範例: hongguo-list -q \"反派親媽\" -n 3 -d              # 背景下載到 ~/Projects/videoapp/data/downloads")
	fmt.Fprintln(os.Stderr, "      hongguo-list -q \"反派親媽\" -n 3 -d --status    # 查看狀態")
	fmt.Fprintln(os.Stderr, "      hongguo-list -q \"反派親媽\" -n 3 --remove 1,3,5-10  # 刪除特定集數")
}

func webSearch(keyword string) ([]SearchResult, error) {
	baseURL := "https://hongguoduanju.com/incent_resource/suggestion"
	params := url.Values{}
	params.Set("app_id", "8662")
	params.Set("query", keyword)
	params.Set("count", "50")

	reqURL := baseURL + "?" + params.Encode()

	client := &http.Client{Timeout: 15 * time.Second}
	req, err := http.NewRequest("GET", reqURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6 Mobile/15E148 Safari/604.1")
	req.Header.Set("Referer", "https://hongguoduanju.com/")
	req.Header.Set("Accept", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var result WebSuggestResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, err
	}

	var items []SearchResult
	for _, it := range result.SuggestList {
		if it.WordType != "short_play_name" || it.VideoData == nil {
			continue
		}
		sid := it.Keyword
		if sid == "" && it.VideoData.SeriesID != "" {
			sid = it.VideoData.SeriesID.String()
		}
		if sid != "" && it.Name != "" {
			items = append(items, SearchResult{
				SeriesID: sid,
				Title:    it.Name,
			})
		}
	}
	return items, nil
}

func extractVideoID(ch core.Chapter) string {
	key := ch.ID
	if strings.HasPrefix(key, "hongguo:") {
		parts := strings.Split(key, ":")
		if len(parts) >= 3 {
			return parts[2]
		}
	}
	return key
}