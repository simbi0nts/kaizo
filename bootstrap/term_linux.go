package main

import (
	"os"
	"syscall"
	"unsafe"
)

var termSaved *syscall.Termios
var keyBuf []byte

func ioctl(req uintptr, t *syscall.Termios) error {
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, 0, req, uintptr(unsafe.Pointer(t))); e != 0 {
		return e
	}
	return nil
}

// termRaw: no line buffering, no echo, non-blocking reads, hidden cursor.
// ISIG stays on, so Ctrl+C still raises SIGINT (the core restores the terminal on it).
func termRaw() error {
	var t syscall.Termios
	if err := ioctl(syscall.TCGETS, &t); err != nil {
		return err
	}
	if termSaved == nil {
		saved := t
		termSaved = &saved
	}
	t.Lflag &^= syscall.ICANON | syscall.ECHO
	t.Cc[syscall.VMIN] = 0
	t.Cc[syscall.VTIME] = 0
	if err := ioctl(syscall.TCSETS, &t); err != nil {
		return err
	}
	os.Stdout.WriteString("\x1b[?25l")
	return nil
}

func termRestore() {
	if termSaved == nil {
		return
	}
	ioctl(syscall.TCSETS, termSaved)
	termSaved = nil
	os.Stdout.WriteString("\x1b[?25h")
}

// termKey returns the next pending key ("" if none): "up" "down" "left" "right" "esc" or the character.
func termKey() string {
	if termSaved != nil {
		buf := make([]byte, 64)
		if n, _ := syscall.Read(0, buf); n > 0 {
			keyBuf = append(keyBuf, buf[:n]...)
		}
	}
	if len(keyBuf) == 0 {
		return ""
	}
	if keyBuf[0] == 0x1b {
		if len(keyBuf) >= 3 && keyBuf[1] == '[' {
			name := map[byte]string{'A': "up", 'B': "down", 'C': "right", 'D': "left"}[keyBuf[2]]
			keyBuf = keyBuf[3:]
			if name == "" {
				return termKey()
			}
			return name
		}
		keyBuf = keyBuf[1:]
		return "esc"
	}
	c := keyBuf[0]
	keyBuf = keyBuf[1:]
	return string(c)
}
