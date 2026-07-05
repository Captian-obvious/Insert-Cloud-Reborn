//go:build windows

/*
A package implementing ANSI Escape sequences as a code driven primative.
*/
package ansi

import (
	"log"
	"runtime"

	"golang.org/x/sys/windows"
)

const (
	Reset        string = "\x1b[0m"
	Black        string = "\x1b[30m"
	Red          string = "\x1b[31m"
	Green        string = "\x1b[32m"
	Yellow       string = "\x1b[33m"
	Blue         string = "\x1b[34m"
	Magenta      string = "\x1b[35m"
	Cyan         string = "\x1b[36m"
	White        string = "\x1b[37m"
	DefaultColor string = "\x1b[39m"
)

func EnableANSI() {
	if runtime.GOOS != "windows" {
		return
	}

	handle, err := windows.GetStdHandle(windows.STD_OUTPUT_HANDLE)
	if err != nil {
		log.Fatal(err)
	}
	var mode uint32
	windows.GetConsoleMode(handle, &mode)
	const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
	windows.SetConsoleMode(handle, mode|ENABLE_VIRTUAL_TERMINAL_PROCESSING)
}
