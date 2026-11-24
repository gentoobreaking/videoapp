package core

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"
)

const (
	moduleIndexFormat  = 1
	moduleIndexBytes   = 1 << 20
	moduleFetchTimeout = 5 * time.Second
)

var nativeModuleIndex = ""

var nativeModuleIndexToken = ""

// moduleIndexAuthHosts 限定模块索引与安装包的 token 认证只用于 GitHub 请求；
// 其他 host（含 release 转址的 objects.githubusercontent.com）绝不携带凭据。
var moduleIndexAuthHosts = map[string]bool{
	"github.com":                true,
	"raw.githubusercontent.com": true,
	"api.github.com":            true,
}

var (
	moduleIndexAddresses = []string{
		"https://cdn.jsdelivr.net/gh/guoapp-modules/index@main/index.json",
	}
	moduleFileAddresses = []string{
		"https://raw.githubusercontent.com/%s/%s/%s",
		"https://cdn.jsdelivr.net/gh/%s@%s/%s",
	}
	moduleIndexRepo    = regexp.MustCompile(`^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$`)
	moduleIndexTag     = regexp.MustCompile(`^(?:[a-z0-9][a-z0-9_-]{0,31}-)?v\d+\.\d+\.\d+$`)
	moduleIndexVersion = regexp.MustCompile(`^\d+\.\d+\.\d+$`)
	moduleIndexHash    = regexp.MustCompile(`^[0-9a-f]{64}$`)
)

type moduleIndexEntry struct {
	ID          string            `json:"id"`
	Name        string            `json:"name"`
	Version     string            `json:"version"`
	Description string            `json:"description"`
	API         int               `json:"api"`
	Adult       bool              `json:"adult"`
	Repo        string            `json:"repo"`
	Tag         string            `json:"tag"`
	SHA256      map[string]string `json:"sha256"`
	Bundled     bool              `json:"bundled,omitempty"`
}

func (entry moduleIndexEntry) usable() bool {
	return entry.API == moduleAPIVersion && moduleIDPattern.MatchString(entry.ID) && strings.TrimSpace(entry.Name) != "" &&
		moduleIndexRepo.MatchString(entry.Repo) && moduleIndexVersion.MatchString(entry.Version) &&
		moduleIndexTag.MatchString(entry.Tag) && (entry.Tag == "v"+entry.Version || entry.Tag == entry.ID+"-v"+entry.Version) &&
		moduleIndexHash.MatchString(entry.SHA256[moduleManifest]) && moduleIndexHash.MatchString(entry.SHA256[moduleEntry])
}

// indexAddresses 返回模块索引用地址；构建期可通过 nativeModuleIndex 注入自持索引，未注入时用官方默认。
func indexAddresses() []string {
	if strings.TrimSpace(nativeModuleIndex) != "" {
		addresses := []string{}
		for _, address := range strings.Split(nativeModuleIndex, ",") {
			if address = strings.TrimRight(strings.TrimSpace(address), "/"); address != "" {
				addresses = append(addresses, address)
			}
		}
		return addresses
	}
	return moduleIndexAddresses
}

func parseModuleIndex(raw []byte) ([]moduleIndexEntry, error) {
	var index struct {
		Format  int                `json:"format"`
		Modules []moduleIndexEntry `json:"modules"`
	}
	if err := json.Unmarshal(raw, &index); err != nil {
		return nil, errors.New("索引格式无效")
	}
	if index.Format != moduleIndexFormat {
		return nil, fmt.Errorf("索引格式为第 %d 版，请更新应用", index.Format)
	}
	entries := []moduleIndexEntry{}
	for _, entry := range index.Modules {
		if entry.usable() {
			entries = append(entries, entry)
		}
	}
	return entries, nil
}

func (engine *nativeEngine) moduleIndex(ctx context.Context) ([]moduleIndexEntry, int, error) {
	var failures []string
	for mirror, address := range indexAddresses() {
		raw, err := engine.fetchModuleResource(ctx, address, moduleIndexBytes)
		if err == nil {
			var entries []moduleIndexEntry
			if entries, err = parseModuleIndex(raw); err == nil {
				return entries, mirror, nil
			}
		}
		failures = append(failures, err.Error())
	}
	return nil, 0, fmt.Errorf("读取模块索引失败：%s", strings.Join(failures, "；"))
}

func (engine *nativeEngine) moduleStore(ctx context.Context) (map[string]any, error) {
	entries, _, err := engine.moduleIndex(ctx)
	bundled := bundledIndexEntries()
	if err != nil && len(bundled) == 0 {
		return nil, err
	}
	items := append(bundled, entries...)
	result := map[string]any{"items": items}
	if err != nil {
		result["warning"] = err.Error()
	}
	return result, nil
}

func (engine *nativeEngine) indexedModulePackage(ctx context.Context, id string, bundled bool) ([]byte, error) {
	if bundled {
		modules, _ := readBundledModules()
		if modules[id].raw == nil {
			return nil, fmt.Errorf("安装包没有内置 %s", id)
		}
		return zipModuleFiles(modules[id].raw, modules[id].code)
	}
	entries, mirror, err := engine.moduleIndex(ctx)
	if err != nil {
		return nil, err
	}
	for _, entry := range entries {
		if entry.ID != id {
			continue
		}
		manifest, err := engine.fetchIndexedFile(ctx, entry, mirror, moduleManifest, moduleManifestBytes)
		if err != nil {
			return nil, err
		}
		code, err := engine.fetchIndexedFile(ctx, entry, mirror, moduleEntry, moduleEntryBytes)
		if err != nil {
			return nil, err
		}
		return zipModuleFiles(manifest, code)
	}
	return nil, fmt.Errorf("模块索引里没有 %s", id)
}

func (engine *nativeEngine) fetchIndexedFile(ctx context.Context, entry moduleIndexEntry, mirror int, name string, limit int) ([]byte, error) {
	var failures []string
	paths := []string{name, entry.ID + "/" + name}
	for _, path := range paths {
		for offset := range moduleFileAddresses {
			pattern := moduleFileAddresses[(mirror+offset)%len(moduleFileAddresses)]
			data, err := engine.fetchModuleResource(ctx, fmt.Sprintf(pattern, entry.Repo, entry.Tag, path), limit)
			if err == nil {
				sum := sha256.Sum256(data)
				if hex.EncodeToString(sum[:]) == entry.SHA256[name] {
					return data, nil
				}
				err = errors.New("文件校验不符")
			}
			failures = append(failures, err.Error())
		}
	}
	return nil, fmt.Errorf("下载 %s 的 %s 失败：%s", entry.Name, name, strings.Join(failures, "；"))
}

func (engine *nativeEngine) fetchModuleResource(ctx context.Context, address string, limit int) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, moduleFetchTimeout)
	defer cancel()
	return engine.fetchLimited(ctx, address, limit)
}

func zipModuleFiles(manifest, code []byte) ([]byte, error) {
	var buffer bytes.Buffer
	archive := zip.NewWriter(&buffer)
	for _, file := range []struct {
		name string
		data []byte
	}{{moduleManifest, manifest}, {moduleEntry, code}} {
		writer, err := archive.Create(file.name)
		if err != nil {
			return nil, err
		}
		if _, err := writer.Write(file.data); err != nil {
			return nil, err
		}
	}
	if err := archive.Close(); err != nil {
		return nil, err
	}
	return buffer.Bytes(), nil
}
