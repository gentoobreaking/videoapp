package core

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
)

// moveDownloads / deleteAllData 的长 I/O 以背景 job 执行：
// 同步阶段只做校验并释放 engine.mu，繁重拷贝/删除在后台 goroutine 完成，
// Dart 端轮询 dataJobStatus 直到结束，避免 620 秒内所有原生呼叫被 engine.mu 塞住。
type nativeDataJob struct {
	mu             sync.Mutex
	kind           string // ""：空闲；"move"：迁移下载目录；"erase"：删除全部资料
	running        bool
	failed         string
	leftoverPath   string
	leftoverReason string
	leftoverList   []string
}

func (engine *nativeEngine) beginDataJob(kind string) error {
	job := &engine.dataJob
	job.mu.Lock()
	defer job.mu.Unlock()
	if job.running {
		return errors.New("上一次资料整理还在进行，请稍后重试")
	}
	job.kind = kind
	job.running = true
	job.failed = ""
	job.leftoverPath = ""
	job.leftoverReason = ""
	job.leftoverList = nil
	return nil
}

func (engine *nativeEngine) finishDataJob(
	kind, failed, leftoverPath, leftoverReason string, leftoverList []string,
) {
	job := &engine.dataJob
	job.mu.Lock()
	defer job.mu.Unlock()
	if job.kind != kind {
		return
	}
	job.kind = ""
	job.running = false
	job.failed = failed
	job.leftoverPath = leftoverPath
	job.leftoverReason = leftoverReason
	job.leftoverList = leftoverList
}

func (engine *nativeEngine) dataJobStatus() map[string]any {
	job := &engine.dataJob
	job.mu.Lock()
	defer job.mu.Unlock()
	return map[string]any{
		"running":        job.running,
		"kind":           job.kind,
		"failed":         job.failed,
		"leftoverPath":   job.leftoverPath,
		"leftoverReason": job.leftoverReason,
		"leftover":       append([]string(nil), job.leftoverList...),
	}
}

func (engine *nativeEngine) startDeleteAllData() error {
	if err := engine.beginDataJob("erase"); err != nil {
		return err
	}
	manager := engine.downloads
	engine.mu.Lock()
	manager.mu.Lock()
	if manager.moving {
		manager.mu.Unlock()
		engine.mu.Unlock()
		return errors.New("下载目录正在处理，请稍后重试")
	}
	if len(manager.converting) > 0 {
		manager.mu.Unlock()
		engine.mu.Unlock()
		return errors.New("请等待下载的分集处理完成后再删除")
	}
	manager.moving = true
	for _, cancel := range manager.active {
		cancel()
	}
	root := manager.root
	manager.mu.Unlock()
	engine.mu.Unlock()
	go func() {
		defer guardBackground(engine.downloader, "data.erase")
		engine.runDeleteAllData(root)
	}()
	return nil
}

func (engine *nativeEngine) runDeleteAllData(root string) {
	var leftover []string
	defer func() { engine.finishDataJob("erase", "", "", "", leftover) }()
	manager := engine.downloads
	manager.workers.Wait()
	if filepath.IsAbs(root) && filepath.Dir(root) != root {
		if err := os.RemoveAll(root); err != nil {
			leftover = append(leftover, root+"："+err.Error())
		}
	}
	leftover = append(leftover, nativeClearDirectory(engine.cacheDirectory)...)
	leftover = append(leftover, nativeClearDirectory(engine.directory)...)
}

func (engine *nativeEngine) startMoveDownloads(parent string) error {
	target := engine.defaultDownloads
	if parent != "" {
		if !filepath.IsAbs(parent) {
			return errors.New("请选择有效的保存目录")
		}
		resolved, err := filepath.EvalSymlinks(parent)
		if err != nil {
			return errors.New("无法打开所选目录")
		}
		target = filepath.Join(filepath.Clean(resolved), "zhenguojian-downloads")
	}
	if err := engine.beginDataJob("move"); err != nil {
		return err
	}
	manager := engine.downloads
	engine.mu.Lock()
	manager.mu.Lock()
	if manager.loadErr != nil {
		manager.mu.Unlock()
		engine.mu.Unlock()
		return errors.New("下载记录无法读取，已停止迁移并保留原索引和文件；请先恢复下载记录")
	}
	if manager.moving {
		manager.mu.Unlock()
		engine.mu.Unlock()
		return errors.New("下载目录正在处理，请稍后重试")
	}
	if len(manager.converting) > 0 {
		manager.mu.Unlock()
		engine.mu.Unlock()
		return errors.New("请等待下载的分集处理完成后再迁移")
	}
	if target == manager.root {
		manager.mu.Unlock()
		engine.mu.Unlock()
		engine.finishDataJob("move", "", "", "", nil)
		return nil
	}
	if nativePathsOverlap(manager.root, target) {
		manager.mu.Unlock()
		engine.mu.Unlock()
		return errors.New("新目录不能与原下载目录互相包含")
	}
	if _, err := os.Stat(target); err == nil {
		manager.mu.Unlock()
		engine.mu.Unlock()
		return errors.New("目标中已有应用下载目录，请选择空目录，避免覆盖文件")
	} else if !os.IsNotExist(err) {
		manager.mu.Unlock()
		engine.mu.Unlock()
		return errors.New("无法检查目标目录：" + err.Error())
	}
	manager.moving = true
	for id, job := range manager.jobs {
		if job.State == "queued" || job.State == "downloading" {
			job.State = "paused"
		}
		if cancel := manager.active[id]; cancel != nil {
			cancel()
		}
	}
	saveErr := manager.saveLocked()
	source := manager.root
	manager.mu.Unlock()
	engine.mu.Unlock()
	if saveErr != nil {
		manager.mu.Lock()
		manager.moving = false
		manager.mu.Unlock()
		engine.finishDataJob("move", "", "", "", nil)
		return saveErr
	}
	go func() {
		defer guardBackground(engine.downloader, "data.move")
		engine.runMoveDownloads(source, target)
	}()
	return nil
}

func (engine *nativeEngine) runMoveDownloads(source, target string) {
	failed, leftoverPath, leftoverReason := "", "", ""
	defer func() { engine.finishDataJob("move", failed, leftoverPath, leftoverReason, nil) }()
	manager := engine.downloads
	manager.workers.Wait()
	resetMoving := func() {
		manager.mu.Lock()
		manager.moving = false
		manager.mu.Unlock()
	}
	if err := os.Mkdir(target, 0700); err != nil {
		resetMoving()
		failed = "无法创建目标目录，请检查权限或选择其他位置"
		return
	}
	if err := nativeCopyTree(context.Background(), source, target); err != nil {
		_ = os.RemoveAll(target)
		resetMoving()
		failed = "文件迁移未完成，原文件已保留，请检查空间与目录权限"
		return
	}
	location := filepath.Join(engine.directory, "download-location.json")
	var persistErr error
	if target == nativeDefaultDownloads(engine.directory) {
		if err := os.Remove(location); !os.IsNotExist(err) {
			persistErr = err
		}
	} else {
		data, _ := json.Marshal(map[string]string{"directory": target})
		persistErr = nativeDownloadWrite(location, data)
	}
	if persistErr != nil {
		_ = os.RemoveAll(target)
		resetMoving()
		failed = "保存下载目录失败，原文件已保留"
		return
	}
	manager.mu.Lock()
	manager.root = target
	manager.moving = false
	manager.mu.Unlock()
	if err := os.RemoveAll(source); err != nil {
		leftoverPath = source
		leftoverReason = err.Error()
	}
}
