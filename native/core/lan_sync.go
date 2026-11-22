package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	lanBroadcastAddr  = "255.255.255.255"
	lanDiscoveryPort  = 19876
	lanDiscoveryToken = "videoapp-lan-sync/1"
	lanScanTimeout    = 6 * time.Second
	lanHTTPTimeout    = 10 * time.Second
	lanDeviceTTL      = 5 * time.Minute
)

// lanDevice 區網內發現的其他裝置資訊。
type lanDevice struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Version string `json:"version"`
	Host    string `json:"host"`
	Port    int    `json:"port"`
}

// lanSyncDevice 區網裝置註冊表項目。
type lanSyncDevice struct {
	info   lanDevice
	expire time.Time
}

// lanSyncInfo 本機裝置資訊。
type lanSyncInfo struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Version string `json:"version"`
	Port    int    `json:"port"`
}

// lanSync 本機 LAN 同步伺服器與發現客戶端。
type lanSync struct {
	mu         sync.Mutex
	wg         sync.WaitGroup
	devices    map[string]*lanSyncDevice
	httpServer *http.Server
	httpPort   int
	discovery  *lanDiscovery
	engine     *nativeEngine
}

// lanDiscovery 負責 UDP 廣播探索。
// Android 11+ 禁止 App 使用 netlink 列舉網路介面（net.Interfaces 會回報
// netlinkrib: permission denied），因此探索改用受限廣播：單一 wildcard
// socket 綁定探索埠並開啟 SO_BROADCAST，全程不需要介面枚舉。
type lanDiscovery struct {
	mu      sync.Mutex
	conn    *net.UDPConn
	running bool
}

// newLanSync 建立 LAN 同步實例（不啟動伺服器）。
func newLanSync(engine *nativeEngine) *lanSync {
	return &lanSync{
		devices: map[string]*lanSyncDevice{},
		engine:  engine,
	}
}

// start 啟動本地 HTTP 伺服器與 UDP 探索。
func (ls *lanSync) start() error {
	ls.mu.Lock()
	defer ls.mu.Unlock()
	if ls.httpServer != nil {
		return nil
	}

	listener, err := net.Listen("tcp4", "0.0.0.0:0") // #nosec G102: LAN sync server needs to bind all interfaces for local network discovery
	if err != nil {
		return fmt.Errorf("無法啟動 LAN 同步伺服器：%w", err)
	}
	ls.httpPort = listener.Addr().(*net.TCPAddr).Port

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/lan/info", ls.handleInfo)
	mux.HandleFunc("/v1/lan/sync/export", ls.handleExport)
	mux.HandleFunc("/v1/lan/sync/import", ls.handleImport)

	ls.httpServer = &http.Server{
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    16384,
	}
	server := ls.httpServer
	ls.wg.Add(1)
	go func() {
		defer ls.wg.Done()
		defer guardBackground(ls.engine.downloader, "lan.http")
		_ = server.Serve(listener)
	}()

	if err := ls.startDiscovery(); err != nil {
		_ = ls.httpServer.Close()
		ls.httpServer = nil
		return fmt.Errorf("無法啟動 LAN 探索：%w", err)
	}

	return nil
}

// stop 停止 LAN 同步伺服器與探索。
func (ls *lanSync) stop() {
	ls.mu.Lock()
	if ls.discovery != nil {
		ls.discovery.stop()
		ls.discovery = nil
	}
	server := ls.httpServer
	ls.httpServer = nil
	ls.devices = map[string]*lanSyncDevice{}
	ls.mu.Unlock()

	if server != nil {
		_ = server.Close()
	}

	ls.wg.Wait()
}

// startDiscovery 啟動 UDP 廣播監聽與定期廣播。
func (ls *lanSync) startDiscovery() error {
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4zero, Port: lanDiscoveryPort})
	if err != nil {
		return err
	}
	if control, ctrlErr := conn.SyscallConn(); ctrlErr == nil {
		_ = control.Control(func(fd uintptr) {
			_ = setBroadcast(fd)
		})
	}
	conn.SetReadBuffer(64 * 1024)
	discovery := &lanDiscovery{conn: conn, running: true}
	ls.discovery = discovery

	ls.wg.Add(1)
	go func() {
		defer ls.wg.Done()
		defer guardBackground(ls.engine.downloader, "lan.discovery")
		defer conn.Close()
		buffer := make([]byte, 64*1024)
		for discovery.isRunning() {
			conn.SetReadDeadline(time.Now().Add(1 * time.Second))
			n, remote, err := conn.ReadFromUDP(buffer)
			if err != nil {
				if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
					continue
				}
				return
			}
			ls.handleDiscoveryMessage(buffer[:n], remote)
		}
	}()

	ls.wg.Add(1)
	go func() {
		defer ls.wg.Done()
		defer guardBackground(ls.engine.downloader, "lan.broadcast")
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		info := ls.localInfo()
		payload, _ := json.Marshal(map[string]any{
			"token":   lanDiscoveryToken,
			"id":      info.ID,
			"name":    info.Name,
			"version": info.Version,
			"port":    info.Port,
		})
		dest := &net.UDPAddr{IP: net.ParseIP(lanBroadcastAddr), Port: lanDiscoveryPort}
		// 立即發送第一次廣播，不等待 ticker 第一次觸發
		conn.WriteToUDP(payload, dest)
		for discovery.isRunning() {
			select {
			case <-ticker.C:
				conn.WriteToUDP(payload, dest)
			}
		}
	}()

	return nil
}

// isRunning 回傳探索是否仍在運行。
func (d *lanDiscovery) isRunning() bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.running
}

// stop 停止探索。
func (d *lanDiscovery) stop() {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.running = false
	if d.conn != nil {
		_ = d.conn.Close()
	}
}

// handleDiscoveryMessage 處理收到的多播發現訊息。
func (ls *lanSync) handleDiscoveryMessage(data []byte, remote *net.UDPAddr) {
	var msg map[string]any
	if err := json.Unmarshal(data, &msg); err != nil {
		return
	}
	if msg["token"] != lanDiscoveryToken {
		return
	}
	id, _ := msg["id"].(string)
	name, _ := msg["name"].(string)
	_, _ = msg["version"].(string)
	port, _ := msg["port"].(float64)
	if id == "" || name == "" || remote.IP.IsLoopback() {
		return
	}

	localInfo := ls.localInfo()
	if id == localInfo.ID {
		return
	}

	host := remote.IP.String()
	ls.mu.Lock()
	defer ls.mu.Unlock()
	ls.devices[id] = &lanSyncDevice{
		info: lanDevice{
			ID:   id,
			Name: name,
			Host: host,
			Port: int(port),
		},
		expire: time.Now().Add(lanDeviceTTL),
	}
}

// localInfo 回傳本機裝置資訊。
func (ls *lanSync) localInfo() lanSyncInfo {
	id, err := ls.engine.installID()
	if err != nil {
		id = "unknown"
	}
	return lanSyncInfo{
		ID:      id,
		Name:    ls.engine.deviceName(),
		Version: "2.0.2+115",
		Port:    ls.httpPort,
	}
}

// handleInfo 處理 /v1/lan/info 請求。
func (ls *lanSync) handleInfo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	info := ls.localInfo()
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(info)
}

// handleExport 處理 /v1/lan/sync/export 請求（遠端裝置抓取本機資料）。
func (ls *lanSync) handleExport(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	data, err := ls.exportSyncData()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Length", fmt.Sprintf("%d", len(data)))
	_, _ = w.Write(data)
}

// handleImport 處理 /v1/lan/sync/import 請求（本機接收遠端資料）。
func (ls *lanSync) handleImport(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 8<<20))
	if err != nil {
		http.Error(w, "read failed", http.StatusBadRequest)
		return
	}
	if err := ls.importSyncData(body); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// exportSyncData 讀取本機 store 目錄，組裝可供 LAN 同步的 JSON 資料。
func (ls *lanSync) exportSyncData() ([]byte, error) {
	storeDir := filepath.Join(ls.engine.directory, "store")
	entries, err := os.ReadDir(storeDir)
	if err != nil {
		return nil, fmt.Errorf("無法讀取存儲目錄：%w", err)
	}

	profiles := []map[string]any{}
	libraries := map[string]json.RawMessage{}

	for _, entry := range entries {
		if !entry.IsDir() || strings.HasPrefix(entry.Name(), ".") {
			continue
		}
		profileID := entry.Name()
		profileDir := filepath.Join(storeDir, profileID)

		// 讀取使用者設定。
		settings, err := os.ReadFile(filepath.Join(profileDir, "settings.json"))
		if err != nil {
			continue
		}
		var settingsMap map[string]any
		if err := json.Unmarshal(settings, &settingsMap); err != nil {
			continue
		}

		// 嘗試從 users.json 讀取 profile 定義。
		usersData, err := os.ReadFile(filepath.Join(storeDir, "users.json"))
		if err != nil {
			continue
		}
		var usersMap map[string]any
		if err := json.Unmarshal(usersData, &usersMap); err != nil {
			continue
		}
		profilesRaw, _ := usersMap["profiles"].([]any)
		var profileInfo map[string]any
		for _, p := range profilesRaw {
			pMap, _ := p.(map[string]any)
			if pMap != nil && pMap["id"] == profileID {
				profileInfo = pMap
				break
			}
		}
		if profileInfo == nil {
			profileInfo = map[string]any{"id": profileID, "name": profileID, "admin": false}
		}

		profiles = append(profiles, profileInfo)

		// 讀取資料庫。
		lib := map[string]json.RawMessage{}
		for _, name := range []string{"history.json", "favorites.json", "followStates.json", "followChecks.json"} {
			data, err := os.ReadFile(filepath.Join(profileDir, name))
			if err != nil {
				lib[name] = json.RawMessage("[]")
				if name == "followStates.json" || name == "followChecks.json" {
					lib[name] = json.RawMessage("{}")
				}
				continue
			}
			lib[name] = data
		}
		raw, _ := json.Marshal(lib)
		libraries[profileID] = raw
	}

	if len(profiles) == 0 {
		return nil, errors.New("無可同步的使用者資料")
	}

	export := map[string]any{
		"schema":    1,
		"app":       "videoapp",
		"profiles":  profiles,
		"libraries": libraries,
	}
	return json.Marshal(export)
}

// importSyncData 將從遠端裝置取得的同步資料寫入本機 store。
func (ls *lanSync) importSyncData(data []byte) error {
	var imp map[string]any
	if err := json.Unmarshal(data, &imp); err != nil {
		return fmt.Errorf("資料格式無效：%w", err)
	}
	if imp["schema"] != float64(1) || imp["app"] != "videoapp" {
		return errors.New("不支持的同步格式")
	}
	profilesRaw, _ := imp["profiles"].([]any)
	if len(profilesRaw) == 0 {
		return errors.New("資料中不含使用者")
	}

	storeDir := ls.engine.directory
	usersFile := filepath.Join(storeDir, "store", "users.json")

	// 讀取現有 users.json。
	usersData, err := os.ReadFile(usersFile)
	if err != nil {
		// 如果文件不存在，創建一個空的 users.json
		usersData = []byte(`{"profiles": [], "active": "", "admin": {}}`)
	}
	var usersMap map[string]any
	if err := json.Unmarshal(usersData, &usersMap); err != nil {
		return fmt.Errorf("使用者設定格式無效：%w", err)
	}

	// 更新 profiles。
	newProfiles := make([]any, len(profilesRaw))
	for i, p := range profilesRaw {
		newProfiles[i] = p
	}
	usersMap["profiles"] = newProfiles

	// 設定 active 為第一個管理員，或第一個使用者。
	activeID := ""
	for _, p := range profilesRaw {
		pMap, _ := p.(map[string]any)
		if pMap != nil && pMap["admin"] == true {
			activeID, _ = pMap["id"].(string)
			break
		}
	}
	if activeID == "" {
		activeID, _ = profilesRaw[0].(map[string]any)["id"].(string)
	}
	usersMap["active"] = activeID

	usersBytes, _ := json.Marshal(usersMap)
	if err := os.WriteFile(usersFile, usersBytes, 0600); err != nil {
		return fmt.Errorf("寫入使用者設定失敗：%w", err)
	}

	// 寫入每個使用者的資料庫。
	librariesRaw, _ := imp["libraries"].(map[string]any)
	for profileID, libRaw := range librariesRaw {
		libMap, _ := libRaw.(map[string]any)
		if libMap == nil {
			continue
		}
		profileDir := filepath.Join(storeDir, "store", profileID)
		if err := os.MkdirAll(profileDir, 0700); err != nil {
			return fmt.Errorf("建立使用者目錄失敗：%w", err)
		}
		for _, name := range []string{"settings.json", "history.json", "favorites.json", "followStates.json", "followChecks.json"} {
			val, ok := libMap[name]
			if !ok {
				continue
			}
			valBytes, err := json.Marshal(val)
			if err != nil {
				return fmt.Errorf("編碼 %s 失敗：%w", name, err)
			}
			if err := os.WriteFile(filepath.Join(profileDir, name), valBytes, 0600); err != nil {
				return fmt.Errorf("寫入 %s 失敗：%w", name, err)
			}
		}
	}

	return nil
}

// scan 掃描區網裝置，回傳發現的裝置清單。
func (ls *lanSync) scan() []lanDevice {
	ls.mu.Lock()
	defer ls.mu.Unlock()
	now := time.Now()
	items := make([]lanDevice, 0, len(ls.devices))
	for _, d := range ls.devices {
		if now.Before(d.expire) {
			items = append(items, d.info)
		}
	}
	sort.Slice(items, func(i, j int) bool { return items[i].Name < items[j].Name })
	return items
}

// syncFromDevice 從指定裝置下載資料並匯入本機。
func (ls *lanSync) syncFromDevice(device lanDevice) error {
	url := fmt.Sprintf("http://%s:%d/v1/lan/sync/export", device.Host, device.Port)
	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	client := &http.Client{Timeout: lanHTTPTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("連線失敗：%w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("對端回應失敗：HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return err
	}
	return ls.importSyncData(body)
}

// nativeLan 處理來自 Dart 層的 LAN 同步請求。
func (engine *nativeEngine) nativeLan(ctx context.Context, input nativeInput) (any, error) {
	command := input.Command
	switch command {
	case "start":
		if err := engine.lanSync.start(); err != nil {
			return nil, err
		}
		info := engine.lanSync.localInfo()
		return map[string]any{"started": true, "port": info.Port}, nil
	case "stop":
		engine.lanSync.stop()
		return map[string]any{"stopped": true}, nil
	case "scan":
		if err := engine.lanSync.start(); err != nil {
			return nil, err
		}
		// 等待一小段時間讓多播發現完成。
		time.Sleep(lanScanTimeout)
		devices := engine.lanSync.scan()
		items := make([]map[string]any, 0, len(devices))
		for _, d := range devices {
			items = append(items, map[string]any{
				"id":      d.ID,
				"name":    d.Name,
				"version": d.Version,
				"host":    d.Host,
				"port":    d.Port,
			})
		}
		return map[string]any{"devices": items}, nil
	case "info":
		if err := engine.lanSync.start(); err != nil {
			return nil, err
		}
		info := engine.lanSync.localInfo()
		return map[string]any{
			"id":      info.ID,
			"name":    info.Name,
			"version": info.Version,
			"port":    info.Port,
		}, nil
	case "sync":
		deviceID := input.Device
		if deviceID == "" {
			return nil, errors.New("未指定目標裝置")
		}
		devices := engine.lanSync.scan()
		var target lanDevice
		found := false
		for _, d := range devices {
			if d.ID == deviceID {
				target = d
				found = true
				break
			}
		}
		if !found {
			return nil, errors.New("未找到指定裝置，請先掃描")
		}
		if err := engine.lanSync.syncFromDevice(target); err != nil {
			return nil, err
		}
		engine.lanSync.stop()
		return map[string]any{"synced": true, "device": target.Name}, nil
	default:
		return nil, errors.New("不支持的 LAN 操作")
	}
}

// deviceName 回傳本機裝置顯示名稱。
func (engine *nativeEngine) deviceName() string {
	hostname, err := os.Hostname()
	if err != nil || hostname == "" {
		return "本裝置"
	}
	return hostname
}
