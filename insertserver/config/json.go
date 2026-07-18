package config

import (
	"encoding/json"
	"os"
	"runtime"
)

type RootConfig struct {
	AcceptsRequests  bool         `json:"AcceptsRequests"`
	HostInfo         HostInfo     `json:"HostInfo"`
	Logging          Logging      `json:"Logging"`
	ServerConfig     ServerConfig `json:"ServerConfig"`
	InstablockFilter []any        `json:"InstablockFilter"`
	GoVersion        string
}

type HostInfo struct {
	ServerName string         `json:"ServerName"`
	AppVersion string         `json:"AppVersion"`
	Additional map[string]any `json:"Additional"`
}

type Logging struct {
	Type          string `json:"type"`
	URL           string `json:"url"`
	RetryDelay    int    `json:"retryDelaySeconds"`
	RetryAttempts int    `json:"retryAttempts"`
	Path          string `json:"path"`
}

type ServerConfig struct {
	FileCachingEnabled     bool   `json:"FileCachingEnabled"`
	JSONCachingEnabled     bool   `json:"JSONCachingEnabled"`
	ChunkCachingEnabled    bool   `json:"ChunkCachingEnabled"`
	CachingMode            string `json:"CachingMode"`
	StringFilteringEnabled bool   `json:"StringFilteringEnabled"`
	LoggingRateLimit       int    `json:"LoggingRateLimit"`
	ConfigReloadRateLimit  int    `json:"ConfigReloadRateLimit"`
	Control                struct {
		WorkingDirectory string `json:"WorkingDirectory"`
		CacheFolderName  string `json:"CacheFolderName"`
	} `json:"Control"`
}

func LoadConfig(path string) (*RootConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg RootConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	cfg.GoVersion = runtime.Version()
	return &cfg, nil
}
