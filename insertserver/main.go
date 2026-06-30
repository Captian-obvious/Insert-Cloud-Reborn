package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"html/template"
	"insertapiv3/ansi"
	"insertapiv3/config"
	"insertapiv3/lib"
	"insertapiv3/middleware"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/context"
	"github.com/gorilla/mux"
)

const USER_AGENT_TEMPLATE string = "Superduperdev2InsertWebservice/3.0 (compatible; %s/%s)"
const ASSET_DELIVERY_URL string = "https://apis.roblox.com/asset-delivery-api/v1/assetId/"

/*
CONFIG STRUCTURE

AcceptsRequests -> live toggle for the entire pipeline

Version -> go version (automatically set (not in config file))

HostInfo.ServerName -> server name, can be anything

HostInfo.AppVersion -> webservice version

HostInfo.Additional (dictionary) -> you can add custom info here if you want

Logging -> configuration for logging

Logging.type -> "webhook", "file" or "disabled"

Logging.url -> webhook URL if using webhook logging

Logging.path -> file path if using file logging

Logging.retryDelaySeconds -> (optional) delay between retries (before exponential backoff) for webhook logging

Logging.retryAttempts -> (optional) number of retry attempts before returning 429 for webhook logging

ServerConfig.JSONCachingEnabled -> Enable or disable caching of parsed JSON files

ServerConfig.Control -> Some information for controlling the server

ServerConfig.Control.RequestTimeoutSeconds -> Request timeout in seconds

ServerConfig.Control.WorkingDirectory -> Working directory for temporary files, also where the code runs from, and where the cache will be created.

ServerConfig.Control.CacheFolderName -> Name of the cache folder inside the working directory (default: "cache")

InstablockFilter -> (optional) list of asset IDs or strings to block instantly
*/
var conf *config.RootConfig
var cachePath string
var USER_AGENT string
var API_KEY string = os.Getenv("RBX_API_KEY")
var lastConfigReload int64
var lastBatchLog int64
var CONFIG_FILE_PATH string = os.Getenv("CONFIG_FILE_PATH")
var STARTED_AT time.Time
var BLOCKED_ASSET_IDS map[float64]struct{}
var assetCooldown sync.Map // map[assetId]time.Time

type LogJson struct {
	AssetId   string `json:"AssetId"`
	UserId    int    `json:"UserId"`
	AssetName string `json:"AssetName"`
	UserName  string `json:"UserName"`
	Source    string `json:"Source"`
	Timestamp string `json:"Timestamp"`
	Type      string `json:"Type"`
	JobId     string `json:"JobId"`
}

type ApiErrorDetailsStruct struct {
	Code  int    `json:"code"`
	Error string `json:"message"`
}

type RobloxApiError struct {
	Errors []ApiErrorDetailsStruct `json:"errors"`
}

type ApiError struct {
	Error        string                  `json:"error"`
	ResponseCode int                     `json:"response_code"`
	Details      []ApiErrorDetailsStruct `json:"details,omitempty"`
}

type AssetThumbnailInfo struct {
	Target          int    `json:"target"`
	State           string `json:"state"`
	ImageUrl        string `json:"imageUrl"`
	Version         string `json:"version"`
	ThumbnailSource string `json:"thumbnailSource"`
}

type AssetThumbnailList struct {
	Data []AssetThumbnailInfo `json:"data"`
}

type AssetMetadata struct {
	Name string `json:"displayName"`
}

type AssetLocationData struct {
	Location     string `json:"location"`
	RequestID    string `json:"requestId"`
	IsArchived   bool   `json:"isArchived"`
	AssetTypeID  int    `json:"assetTypeId"`
	IsRecordable bool   `json:"isRecordable"`
}

type OutputRBXM struct {
	Metadata      map[string]any      `json:"metadata"`
	ClassCount    uint32              `json:"class_count"`
	InstanceCount uint32              `json:"instance_count"`
	ClassRef      []lib.ClassRefEntry `json:"class_ref"`
	Tree          []*lib.Instance     `json:"tree"`
}

type ErrorPageData struct {
	Title string
	Img   string
	Text1 string
	Text2 string
}

type AudioViewerPageData struct {
	AssetId      int
	AssetName    string
	CacheSource  string
	ThumbnailUrl string
}

var DISABLED_ERROR ApiError = ApiError{
	Error:        "Could not fetch asset because api returned errors",
	ResponseCode: 503,
	Details: []ApiErrorDetailsStruct{
		{
			Code:  -1,
			Error: "The Insert Cloud is currently OFFLINE",
		},
	},
}

func main() {
	ansi.EnableANSI()
	appname := os.Getenv("APP_NAME")
	if appname == "" {
		appname = "InsertCloudAPIV3"
	}
	if CONFIG_FILE_PATH == "" {
		CONFIG_FILE_PATH = "server_config.json"
	}
	fmt.Println("Running Application: " + appname)
	fmt.Print(ansi.Cyan + `
                                                                                          
▄▄▄▄▄                                  ▄▄▄▄▄▄▄ ▄▄                ▄▄   ▄▄▄▄  ▄▄▄▄ ▄▄▄▄▄▄▄  
 ███                           ██     ███▀▀▀▀▀ ██                ██   ▀███  ███▀ ▀▀▀▀████ 
 ███  ████▄ ▄█▀▀▀ ▄█▀█▄ ████▄ ▀██▀▀   ███      ██ ▄███▄ ██ ██ ▄████    ███  ███    ▄▄██▀  
 ███  ██ ██ ▀███▄ ██▄█▀ ██ ▀▀  ██     ███      ██ ██ ██ ██ ██ ██ ██    ███▄▄███      ███▄ 
▄███▄ ██ ██ ▄▄▄█▀ ▀█▄▄▄ ██     ██     ▀███████ ██ ▀███▀ ▀██▀█ ▀████     ▀████▀   ███████▀ 
                                                                                          
                                                                                          
                                ` + ansi.Red + `by Superduperdev2 Inc.                                 
` + ansi.Reset + "\n")
	STARTED_AT = time.Now()
	lastConfigReload = STARTED_AT.UnixNano()
	lastBatchLog = STARTED_AT.UnixNano()
	err := ReloadConfig(CONFIG_FILE_PATH)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}
	USER_AGENT = fmt.Sprintf(USER_AGENT_TEMPLATE, conf.HostInfo.ServerName, conf.HostInfo.AppVersion)
	fmt.Println("Loaded filter entries:", len(conf.InstablockFilter))
	stringEnabled := conf.ServerConfig.StringFilteringEnabled
	color := ansi.Red
	if stringEnabled {
		color = ansi.Green
	}
	fmt.Println("String filtering enabled: "+color, stringEnabled, ansi.Reset)
	log.New(os.Stdout, "", log.LstdFlags)
	port := os.Getenv("PORT")
	if port == "" {
		port = "5000"
	}
	if err := os.MkdirAll(cachePath, 0755); err != nil {
		log.Fatal("Failed to create required cache directory")
	}
	r := mux.NewRouter()
	//free logging middleware yay!
	r.Use(middleware.LoggingMiddleware)
	// now our webserver actually begins
	r.PathPrefix("/static/").Handler(http.StripPrefix("/static/", http.FileServer(http.Dir("assets/"))))
	r.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, "public/index.html")
	}).Methods("GET")
	r.HandleFunc("/favicon.ico", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, "assets/images/favicon.ico")
	}).Methods("GET")
	r.NotFoundHandler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
		fmt.Fprintf(w, "%s", `<script>document.location.href="/request_error?code=404"</script>`)
	})
	r.MethodNotAllowedHandler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusMethodNotAllowed)
		fmt.Fprintf(w, "%s", `<script>document.location.href="/request_error?code=405"</script>`)
	})
	r.HandleFunc("/api/v3/asset/{assetId}", get_asset).Methods("GET")
	r.HandleFunc("/api/v3/parse", ParseHandler).Methods("POST")
	r.HandleFunc("/api/v2/asset/{assetId}", get_asset_v2).Methods("GET")
	r.HandleFunc("/api/v1/asset/{assetId}", get_asset_old).Methods("GET")
	r.HandleFunc("/server.py", ServerStatus).Methods("GET")
	r.HandleFunc("/audio/{assetId}", AudioViewerHandler).Methods("GET")
	r.HandleFunc("/logger", LoggerHandler).Methods("POST")
	r.HandleFunc("/request_error", ErrorPageMethod).Methods("GET")
	fmt.Println("Listening on port :" + ansi.Green + port + ansi.Reset)
	log.Fatal(http.ListenAndServe(":"+port, context.ClearHandler(r)))
}

func get_asset(w http.ResponseWriter, r *http.Request) {
	ReloadConfig(CONFIG_FILE_PATH)
	if !conf.AcceptsRequests {
		w.WriteHeader(http.StatusServiceUnavailable)
		if err := json.NewEncoder(w).Encode(DISABLED_ERROR); err != nil {
			log.Fatal(err)
		}
		return
	}
	muxVars := mux.Vars(r)
	assetId := muxVars["assetId"]
	query := r.URL.Query()
	placeId := query.Get("placeId")
	version := query.Get("version")
	assetType := query.Get("type")
	w.Header().Set("Content-Type", "application/json")
	if placeId == "" {
		w.WriteHeader(400)
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Missing required query parameter \"placeId\"",
			ResponseCode: 400,
		})
		return
	}
	_, err := strconv.ParseInt(placeId, 10, 0)
	aidInt, err2 := strconv.ParseInt(assetId, 10, 0) // prevents injection attacks
	if err != nil || err2 != nil || strings.Contains(assetType, "\r\n") {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Invalid Parameters supplied",
			ResponseCode: 400,
		})
		return
	}
	if _, blocked := BLOCKED_ASSET_IDS[float64(aidInt)]; blocked {
		w.WriteHeader(http.StatusForbidden)
		fmt.Fprint(w, "")
		return
	}
	FINAL_URL := ASSET_DELIVERY_URL + assetId
	if version != "" {
		_, err3 := strconv.ParseInt(version, 10, 0) // prevents injection attacks
		if err3 != nil {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(ApiError{
				Error:        "Invalid Parameters supplied",
				ResponseCode: 400,
			})
			return
		}
		FINAL_URL = FINAL_URL + "/version/" + version
	}

	data := fetchAssetData(FINAL_URL, placeId, assetType, w)
	if data == "" {
		return
	}
	switch assetType {
	case "Audio":
		w.Header().Set("Content-Type", "audio/ogg")
		fmt.Fprint(w, data)
		return
	case "Image":
		w.Header().Set("Content-Type", "image/png")
		fmt.Fprint(w, data)
		return
	case "Mesh":
		w.Header().Set("Content-Type", "text/plain")
		fmt.Fprint(w, data)
	default:
		ParseRBXM(w, data, assetId, version)
	}
}
func get_asset_v2(w http.ResponseWriter, r *http.Request) {
	ReloadConfig(CONFIG_FILE_PATH)
	if !conf.AcceptsRequests {
		w.WriteHeader(http.StatusServiceUnavailable)
		if err := json.NewEncoder(w).Encode(DISABLED_ERROR); err != nil {
			log.Fatal(err)
		}
		return
	}
	muxVars := mux.Vars(r)
	assetId := muxVars["assetId"]
	query := r.URL.Query()
	placeId := query.Get("placeId")
	version := query.Get("version")
	w.Header().Set("Content-Type", "application/json")
	if placeId == "" {
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Missing required query parameter \"placeId\"",
			ResponseCode: 400,
		})
		return
	}
	_, err := strconv.ParseInt(placeId, 10, 0)
	aidInt, err2 := strconv.ParseInt(assetId, 10, 0) // prevents injection attacks
	if err != nil || err2 != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Invalid Parameters supplied",
			ResponseCode: 400,
		})
		return
	}
	if _, blocked := BLOCKED_ASSET_IDS[float64(aidInt)]; blocked {
		w.WriteHeader(http.StatusForbidden)
		fmt.Fprint(w, "")
		return
	}
	FINAL_URL := ASSET_DELIVERY_URL + assetId
	if version != "" {
		_, err3 := strconv.ParseInt(version, 10, 0) // prevents injection attacks
		if err3 != nil {
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(ApiError{
				Error:        "Invalid Parameters supplied",
				ResponseCode: 400,
			})
			return
		}
		FINAL_URL = FINAL_URL + "/version/" + version
	}

	data := fetchAssetData(FINAL_URL, placeId, "Model", w)
	if data == "" {
		return
	}
	ParseRBXM(w, data, assetId, version)
}
func get_asset_old(w http.ResponseWriter, r *http.Request) {
	ReloadConfig(CONFIG_FILE_PATH)
	if !conf.AcceptsRequests {
		w.WriteHeader(http.StatusServiceUnavailable)
		if err := json.NewEncoder(w).Encode(DISABLED_ERROR); err != nil {
			log.Fatal(err)
		}
		return
	}

	muxVars := mux.Vars(r)
	assetId := muxVars["assetId"]
	query := r.URL.Query()
	placeId := query.Get("placeId")
	version := query.Get("version")
	assetType := query.Get("type")
	if placeId == "" {
		w.WriteHeader(400)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Missing required query parameter \"placeId\"",
			ResponseCode: 400,
		})
		return
	}
	_, err := strconv.ParseInt(placeId, 10, 0)
	aidInt, err2 := strconv.ParseInt(assetId, 10, 0) // prevents injection attacks
	if err != nil || err2 != nil || strings.Contains(assetType, "\r\n") {
		w.WriteHeader(http.StatusBadRequest)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Invalid Parameters supplied",
			ResponseCode: 400,
		})
		return
	}
	if _, blocked := BLOCKED_ASSET_IDS[float64(aidInt)]; blocked {
		w.WriteHeader(http.StatusForbidden)
		fmt.Fprint(w, "")
		return
	}
	FINAL_URL := ASSET_DELIVERY_URL + assetId
	if version != "" {
		_, err3 := strconv.ParseInt(version, 10, 0) // prevents injection attacks
		if err3 != nil {
			w.WriteHeader(http.StatusBadRequest)
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(ApiError{
				Error:        "Invalid Parameters supplied",
				ResponseCode: 400,
			})
			return
		}
		FINAL_URL = FINAL_URL + "/version/" + version
	}
	data := fetchAssetData(FINAL_URL, placeId, assetType, w)
	if data == "" {
		return
	}
	switch assetType {
	case "Audio":
		w.Header().Set("Content-Type", "audio/ogg")
		fmt.Fprint(w, data)
		return
	case "Image":
		w.Header().Set("Content-Type", "image/png")
		fmt.Fprint(w, data)
		return
	default:
		w.Header().Set("Content-Type", "text/plain")
		fmt.Fprint(w, data)
	}
}

func AudioViewerHandler(w http.ResponseWriter, r *http.Request) {
	muxVars := mux.Vars(r)
	assetId := muxVars["assetId"]
	query := r.URL.Query()
	placeId := query.Get("placeId")
	if placeId == "" {
		w.WriteHeader(http.StatusBadRequest)
		fmt.Fprint(w, "Missing required query \"placeId\", Audio will not load.")
		return
	}
	_, err := strconv.ParseInt(placeId, 10, 0)
	assetIdInt, err2 := strconv.ParseInt(assetId, 10, 0) // prevents injection attacks
	if err != nil || err2 != nil {
		w.WriteHeader(http.StatusBadRequest)
		fmt.Fprint(w, "Invalid Parameters Supplied, Audio will not load.")
		return
	}
	thumbnail := ""
	assetName := ""
	res, err := http.Get(fmt.Sprintf("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=420x420&format=Png&isCircular=false", assetId))
	if err != nil {
		fmt.Println("Failed to fetch asset info.")
	} else {
		switch res.StatusCode {
		case 200:
			var data AssetThumbnailList
			err := json.NewDecoder(res.Body).Decode(&data)
			if err != nil {
				fmt.Println("Failed to fetch asset info.")
			} else {
				thumbnail = data.Data[0].ImageUrl
			}
		default:
			fmt.Println("Failed to fetch asset info.")
		}
	}
	assetInfoFetchReq, err := http.NewRequest("GET", fmt.Sprintf("https://apis.roblox.com/assets/v1/assets/%s", assetId), nil)
	if err != nil {
		fmt.Println("Failed to fetch asset info. (request creation failed)")
	} else {
		assetInfoFetchReq.Header.Set("x-api-key", API_KEY)
		assetInfoFetchReq.Header.Set("User-Agent", USER_AGENT)
		res2, err := http.DefaultClient.Do(assetInfoFetchReq)
		if err != nil {
			fmt.Println("Failed to fetch asset info. (request failed)")
		} else {
			switch res2.StatusCode {
			case 200:
				var assetData AssetMetadata
				err := json.NewDecoder(res2.Body).Decode(&assetData)
				if err != nil {
					fmt.Println("Failed to fetch asset info.")
				} else {
					assetName = assetData.Name
				}
			default:
				fmt.Println("Failed to fetch asset info.")
			}
		}
	}
	tmpl, err := template.ParseFiles("templates/audio_player.html")
	if err != nil {
		log.Fatal(err)
	}
	tmpl.Execute(w, AudioViewerPageData{
		CacheSource:  fmt.Sprintf("/api/v3/asset/%s?placeId=%s&type=Audio", assetId, placeId),
		AssetId:      int(assetIdInt),
		ThumbnailUrl: thumbnail,
		AssetName:    assetName,
	})
}

func ParseHandler(w http.ResponseWriter, r *http.Request) {
	ReloadConfig(CONFIG_FILE_PATH)
	w.Header().Set("Content-Type", "application/json")
	if !conf.AcceptsRequests {
		w.WriteHeader(http.StatusServiceUnavailable)
		if err := json.NewEncoder(w).Encode(DISABLED_ERROR); err != nil {
			log.Fatal(err)
		}
		return
	}
	content, _ := io.ReadAll(r.Body)
	assetDataRaw, err := base64.StdEncoding.DecodeString(string(content))
	if err != nil {
		w.WriteHeader(500)
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Failed to base64 decode data",
			ResponseCode: 500,
			Details: []ApiErrorDetailsStruct{
				{
					Error: string(err.Error()),
					Code:  -1,
				},
			},
		})
		return
	}
	rbxm, err := lib.Parse(string(assetDataRaw))
	if err != nil {
		w.WriteHeader(500)
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Failed to parse data",
			ResponseCode: 500,
			Details: []ApiErrorDetailsStruct{
				{
					Error: string(err.Error()),
					Code:  -1,
				},
			},
		})
		return
	}
	jsonData := OutputRBXM{
		Metadata:      rbxm.Metadata,
		ClassCount:    rbxm.ClassCount,
		InstanceCount: rbxm.InstanceCount,
		ClassRef:      rbxm.ClassRef,
		Tree:          rbxm.Tree,
	}
	err = json.NewEncoder(w).Encode(jsonData)
	if err != nil {
		w.WriteHeader(500)
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Failed to json encode data",
			ResponseCode: 500,
			Details: []ApiErrorDetailsStruct{
				{
					Error: string(err.Error()),
					Code:  -1,
				},
			},
		})
		return
	}
}

func ErrorPageMethod(w http.ResponseWriter, r *http.Request) {
	code := r.URL.Query().Get("code")
	if code == "" {
		code = "404"
	}
	code_int, err := strconv.ParseInt(code, 10, 0)
	if err != nil {
		fmt.Fprintf(w, "%s", err.Error())
		return
	}
	w.WriteHeader(int(code_int))
	img, title, text1, text2 := "", "", "", ""
	switch code_int {
	case 400:
		img = "/static/images/Error.png"
		title = "Uh Oh!"
		text1 = "Something's off with that request. Try double-checking your input."
		text2 = "HTTP_Bad_Request"
	case 401:
		img = "/static/images/Error.png"
		title = "Uh Oh!"
		text1 = "Looks like you're not signed in, let's fix that!"
		text2 = "HTTP_Unauthorized"
	case 403:
		img = "/static/images/Error.png"
		title = "Access Denied!"
		text1 = "You don't have permission to view this page. Need help?"
		text2 = "HTTP_Forbidden"
	case 405:
		img = "/static/images/Erro2.png"
		title = "Access Denied!"
		text1 = "Something with that request wasnt quite right. Did you access it correctly?"
		text2 = "HTTP_Method_Not_Allowed"
	case 500:
		img = "/static/images/Error.png"
		title = "Uh oh!"
		text1 = "Looks like our servers hit a snag. We’re working on it!"
		text2 = "HTTP_Internal_Server_Error"
	case 502:
		img = "/static/images/bad_gateway.png"
		title = "Uh oh!"
		text1 = "The connection got a bit messy. Try refreshing."
		text2 = "HTTP_Bad_Gateway"
	case 503:
		img = "/static/images/Error.png"
		title = "Something went wrong"
		text1 = "We’re taking a quick nap. Check back soon!"
		text2 = "HTTP_Service_Unavailable"
	default:
		img = "/static/images/Erro2.png"
		title = "Page not found."
		text1 = "Looks like this page wandered off. Maybe check the URL?"
		text2 = "HTTP_Page_Not_Found"
	}
	tmpl, err := template.ParseFiles("templates/request_error.html")
	if err != nil {
		log.Fatal(err)
	}
	tmpl.Execute(w, ErrorPageData{
		Title: title,
		Img:   img,
		Text1: text1,
		Text2: text2,
	})
}

func LoggerHandler(w http.ResponseWriter, r *http.Request) {
	ReloadConfig(CONFIG_FILE_PATH)
	query := r.URL.Query()
	TIME_NOW := time.Now()
	logType := query.Get("type")
	if logType == "" {
		logType = "asset"
	}
	content, _ := io.ReadAll(r.Body)
	logString := ""
	w.Header().Set("Content-Type", "application/json")
	var LogData LogJson
	if err := json.Unmarshal(content, &LogData); err != nil {
		w.WriteHeader(500)
		fmt.Println(err.Error())
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Failed to decode JSON",
			ResponseCode: 500,
			Details: []ApiErrorDetailsStruct{
				{
					Error: err.Error(),
					Code:  -1,
				},
			},
		})
		return
	}
	switch logType {
	case "asset":
		if LogData.AssetId == "" || LogData.UserId == 0 {
			w.WriteHeader(400)
			json.NewEncoder(w).Encode(ApiError{
				Error:        "Invalid Model Log Entry provided",
				ResponseCode: 400,
			})
			return
		}
		jobIdString := ""
		if LogData.AssetName == "" {
			LogData.AssetName = "unknown_asset"
		}
		if LogData.UserName == "" {
			LogData.UserName = "unknown_user"
		}
		if LogData.JobId != "" {
			jobIdString = " in serverId " + LogData.JobId
		}
		logString = fmt.Sprintf("[%s] User %s (%d) loaded asset %s (%s)%s", TIME_NOW.Format(time.RFC3339), formatInjectDefense(LogData.UserName), LogData.UserId, formatInjectDefense(LogData.AssetName), formatInjectDefense(LogData.AssetId), formatInjectDefense(jobIdString))
	case "script":
		if LogData.Source == "" || LogData.Timestamp == "" || LogData.UserId == 0 {
			w.WriteHeader(400)
			json.NewEncoder(w).Encode(ApiError{
				Error:        "Invalid Script Log Entry provided",
				ResponseCode: 400,
			})
			return
		}
		jobIdString := ""
		if LogData.UserName == "" {
			LogData.UserName = "unknown_user"
		}
		if LogData.JobId != "" {
			jobIdString = " in serverId " + LogData.JobId
		}
		logString = fmt.Sprintf("[%s] User %s (%d) ran a %s script at %s%s. View its source at path -> %s", TIME_NOW.Format(time.RFC3339), formatInjectDefense(LogData.UserName), LogData.UserId, formatInjectDefense(LogData.Type), formatInjectDefense(LogData.Timestamp), formatInjectDefense(jobIdString), "/test/script.lua")
	}
	LogEntry(logString)
	json.NewEncoder(w).Encode(map[string]any{
		"message": "logged successfully!",
	})
}

func ServerStatus(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(map[string]any{
		"AcceptsRequests": conf.AcceptsRequests,
		"Version":         conf.GoVersion,
		"HostInfo":        conf.HostInfo,
		"UptimeInfo":      GetUptime(),
	}); err != nil {
		log.Fatal(err)
	}
}

func GetUptime() map[string]string {
	now := time.Now()
	uptime := now.Sub(STARTED_AT)
	return map[string]string{
		"started_at":   STARTED_AT.Format(time.RFC3339),
		"current_time": now.Format(time.RFC3339),
		"uptime":       uptime.String(),
	}
}

func fetchAssetData(FINAL_URL string, placeId string, assetType string, w http.ResponseWriter) string {
	if assetType == "" {
		assetType = "Model"
	}

	req, err := http.NewRequest("GET", FINAL_URL, nil)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ApiError{
			Error:        "An error occured while constructing request",
			ResponseCode: 500,
		})
		return ""
	}
	req.Header.Set("x-api-key", API_KEY)
	req.Header.Set("Roblox-Place-Id", placeId)
	req.Header.Set("AssetType", assetType)
	req.Header.Set("User-Agent", USER_AGENT)
	req.Header.Set("Accept", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		w.WriteHeader(http.StatusBadGateway)
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Upstream server did not respond to request",
			ResponseCode: 502,
		})
		return ""
	}
	//fmt.Printf("%s %s (%d)\n", "Response Code: ", res.Status, res.StatusCode)
	rets := ""
	switch res.StatusCode {
	case 200:
		var data AssetLocationData
		if err := json.NewDecoder(res.Body).Decode(&data); err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			json.NewEncoder(w).Encode(ApiError{
				Error:        "An error occured while decoding",
				ResponseCode: 500,
			})
			break
		}
		res2, err := http.Get(data.Location)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			json.NewEncoder(w).Encode(ApiError{
				Error:        "An error occured while fetching asset",
				ResponseCode: 500,
			})
			break
		}
		if res2.StatusCode == 200 {
			resdata, err := io.ReadAll(res2.Body)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				json.NewEncoder(w).Encode(ApiError{
					Error:        "An error occured while fetching asset",
					ResponseCode: 500,
				})
			}
			rets = string(resdata)
			break
		}
	case 403:
		w.WriteHeader(http.StatusForbidden)
		var details RobloxApiError
		json.NewDecoder(res.Body).Decode(&details)

		json.NewEncoder(w).Encode(ApiError{
			Error:        "User is not authorized to access asset.",
			ResponseCode: 403,
			Details:      details.Errors,
		})
	/*case 429:
		retryAfter := res.Header.Get("Retry-After")
		if retryAfter != "" {
			secs, _ := strconv.Atoi(retryAfter)
			cooldownUntil := time.Now().Add(time.Duration(secs) * time.Second)

			assetCooldown.Store(FINAL_URL, cooldownUntil)
		}*/
	default:
		w.WriteHeader(res.StatusCode)
		var details RobloxApiError
		json.NewDecoder(res.Body).Decode(&details)
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Could not fetch asset because api returned errors",
			ResponseCode: res.StatusCode,
			Details:      details.Errors,
		})
	}
	return rets
}

func ParseRBXM(w http.ResponseWriter, data string, assetId string, version string) {
	rawPath := filepath.Join(cachePath, "raw")
	jsonPath := filepath.Join(cachePath, "json")
	verStr := "_" + version
	if version == "" {
		verStr = ""
	}
	if conf.ServerConfig.FileCachingEnabled {
		os.MkdirAll(rawPath, 0755)
		file, err := os.Create(filepath.Join(rawPath, assetId+verStr+".rbxm"))
		if err != nil {
			log.Println("failed to create cache file! " + err.Error())
		} else {
			file.WriteString(data)
		}
	}
	if conf.ServerConfig.JSONCachingEnabled {
		os.MkdirAll(jsonPath, 0755)
	}
	rbxm, err := lib.Parse(data)
	if err != nil {
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Failed to parse data",
			ResponseCode: 500,
			Details: []ApiErrorDetailsStruct{
				{
					Error: string(err.Error()),
					Code:  -1,
				},
			},
		})
		return
	}
	jsonData := OutputRBXM{
		Metadata:      rbxm.Metadata,
		ClassCount:    rbxm.ClassCount,
		InstanceCount: rbxm.InstanceCount,
		ClassRef:      rbxm.ClassRef,
		Tree:          rbxm.Tree,
	}
	jDat, err := json.Marshal(jsonData)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ApiError{
			Error:        "Failed to json encode data",
			ResponseCode: 500,
			Details: []ApiErrorDetailsStruct{
				{
					Error: string(err.Error()),
					Code:  -1,
				},
			},
		})
		log.Print("An error occured while parsing data: "+err.Error())
		return
	}
	fmt.Fprint(w, string(jDat))
}

func ReloadConfig(path string) error {
	now := time.Now().UnixNano()
	last := atomic.LoadInt64(&lastConfigReload)
	if conf != nil {
		if now-last < (int64(time.Second) * int64(conf.ServerConfig.LoggingRateLimit)) {
			return nil
		}
		if !atomic.CompareAndSwapInt64(&lastConfigReload, last, now) {
			return nil
		}
	}
	cfg, err := config.LoadConfig(path)
	if err != nil {
		return err
	}
	conf = cfg
	cachePath = conf.ServerConfig.Control.WorkingDirectory + "/" + conf.ServerConfig.Control.CacheFolderName
	filterRulesAssetId := []float64{}
	filterRulesString := []string{}
	for _, v := range conf.InstablockFilter {
		switch v := v.(type) {
		case float64, float32:
			val := v.(float64)
			filterRulesAssetId = append(filterRulesAssetId, val)
		case string:
			filterRulesString = append(filterRulesString, v)
		default:
			continue
		}
	}
	BLOCKED_ASSET_IDS = make(map[float64]struct{})
	for i := 0; i < len(filterRulesAssetId); i++ {
		BLOCKED_ASSET_IDS[filterRulesAssetId[i]] = struct{}{}
	}
	return nil
}

func LogEntry(logString string) {
	switch conf.Logging.Type {
	case "stdout":
		fmt.Println(logString)
	}
}

func formatInjectDefense(str string) string {
	return strings.ReplaceAll(strings.ReplaceAll(str, "%", "%%"), "\n", "\\n")
}
