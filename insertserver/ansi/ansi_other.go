//go:build !windows

/*
A package implementing ANSI Escape sequences as a code driven primative.
*/
package ansi

const (
	Reset              string = "\x1b[0m"
	Bold               string = "\x1b[1m"
	Dim                string = "\x1b[2m"
	Italic             string = "\x1b[3m"
	Underline          string = "\x1b[4m"
	Blinking           string = "\x1b[5m"
	InvRev             string = "\x1b[7m"
	Hidden             string = "\x1b[8m"
	Strikethrough      string = "\x1b[9m"
	ResetBoldOrDim     string = "\x1b[22m"
	ResetItalic        string = "\x1b[23m"
	ResetUnderline     string = "\x1b[24m"
	ResetBlinking      string = "\x1b[25m"
	ResetInvRev        string = "\x1b[27m"
	ResetHidden        string = "\x1b[28m"
	ResetStrikethrough string = "\x1b[29m"
	Black              string = "\x1b[30m"
	Red                string = "\x1b[31m"
	Green              string = "\x1b[32m"
	Yellow             string = "\x1b[33m"
	Blue               string = "\x1b[34m"
	Magenta            string = "\x1b[35m"
	Cyan               string = "\x1b[36m"
	White              string = "\x1b[37m"
	DefaultColor       string = "\x1b[39m"
	BlackBg            string = "\x1b[40m"
	RedBg              string = "\x1b[41m"
	GreenBg            string = "\x1b[42m"
	YellowBg           string = "\x1b[43m"
	BlueBg             string = "\x1b[44m"
	MagentaBg          string = "\x1b[45m"
	CyanBg             string = "\x1b[46m"
	WhiteBg            string = "\x1b[47m"
	DefaultColorBg     string = "\x1b[49m"
)

func EnableANSI() {
	// No-op: Linux, macOS, PowerShell, Windows Terminal already support ANSI
}
