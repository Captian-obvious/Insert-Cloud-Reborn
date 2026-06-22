//go:build !windows

/*
A package implementing ANSI Escape sequences as a code driven primative.
*/
package ansi

const (
	Reset        = "\x1b[0m"
	Black        = "\x1b[30m"
	Red          = "\x1b[31m"
	Green        = "\x1b[32m"
	Yellow       = "\x1b[33m"
	Blue         = "\x1b[34m"
	Magenta      = "\x1b[35m"
	Cyan         = "\x1b[36m"
	White        = "\x1b[37m"
	DefaultColor = "\x1b[39m"
)

func EnableANSI() {
	// No-op: Linux, macOS, PowerShell, Windows Terminal already support ANSI
}
