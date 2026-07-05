//go:build !windows

/*
A package implementing ANSI Escape sequences as a code driven primative.
*/
package ansi

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
	// No-op: Linux, macOS, PowerShell, Windows Terminal already support ANSI
}
