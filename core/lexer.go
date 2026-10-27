package main

import (
	"fmt"
	"strconv"
	"strings"
)

type Pos struct {
	File      string
	Line, Col int
}

func (p Pos) String() string { return fmt.Sprintf("%s:%d:%d", p.File, p.Line, p.Col) }

// Diag is a compile-time diagnostic. Hint is a suggested fix for the agent's repair loop.
type Diag struct {
	At   Pos    `json:"-"`
	Msg  string `json:"message"`
	Hint string `json:"hint,omitempty"`
}

func (d Diag) Error() string {
	s := d.At.String() + ": error: " + d.Msg
	if d.Hint != "" {
		s += "\n  hint: " + d.Hint
	}
	return s
}

type TokKind int

const (
	TEOF TokKind = iota
	TIdent
	TUpper
	TInt
	TStr
	TKw
	TPunct
)

type Token struct {
	Kind TokKind
	Text string
	Int  int64
	At   Pos
}

var keywords = map[string]bool{
	"fn": true, "end": true, "let": true, "if": true, "then": true, "elif": true,
	"else": true, "match": true, "case": true, "type": true, "test": true,
	"import": true, "with": true, "true": true, "false": true,
}

func isLetter(c byte) bool { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') }
func isDigit(c byte) bool  { return c >= '0' && c <= '9' }

func lex(file, src string) ([]Token, error) {
	var toks []Token
	line, col, i := 1, 1, 0
	adv := func() {
		if src[i] == '\n' {
			line++
			col = 1
		} else {
			col++
		}
		i++
	}
	for i < len(src) {
		c := src[i]
		at := Pos{file, line, col}
		switch {
		case c == ' ' || c == '\t' || c == '\r' || c == '\n':
			adv()
		case c == '#':
			for i < len(src) && src[i] != '\n' {
				adv()
			}
		case isLetter(c) || c == '_':
			j := i
			for j < len(src) && (isLetter(src[j]) || isDigit(src[j]) || src[j] == '_') {
				j++
			}
			text := src[i:j]
			for i < j {
				adv()
			}
			kind := TIdent
			switch {
			case text == "_":
				kind = TPunct
			case keywords[text]:
				kind = TKw
			case c >= 'A' && c <= 'Z':
				kind = TUpper
			}
			toks = append(toks, Token{Kind: kind, Text: text, At: at})
		case isDigit(c) || (c == '-' && i+1 < len(src) && isDigit(src[i+1])):
			j := i + 1
			for j < len(src) && isDigit(src[j]) {
				j++
			}
			text := src[i:j]
			n, err := strconv.ParseInt(text, 10, 64)
			if err != nil {
				return nil, Diag{At: at, Msg: "integer literal out of range: " + text}
			}
			for i < j {
				adv()
			}
			toks = append(toks, Token{Kind: TInt, Text: text, Int: n, At: at})
		case c == '"':
			adv()
			var sb strings.Builder
			for {
				if i >= len(src) || src[i] == '\n' {
					return nil, Diag{At: at, Msg: "unterminated string", Hint: `strings are one line; write \n for a newline`}
				}
				ch := src[i]
				if ch == '"' {
					adv()
					break
				}
				if ch == '\\' && i+1 < len(src) {
					esc := map[byte]byte{'n': '\n', 't': '\t', 'r': '\r', '0': 0, 'e': 0x1b, '\\': '\\', '"': '"'}
					r, ok := esc[src[i+1]]
					if !ok {
						return nil, Diag{At: Pos{file, line, col}, Msg: fmt.Sprintf("unknown escape \\%c", src[i+1]),
							Hint: `known escapes: \n \t \r \0 \e (ESC) \\ \"`}
					}
					sb.WriteByte(r)
					adv()
					adv()
					continue
				}
				sb.WriteByte(ch)
				adv()
			}
			toks = append(toks, Token{Kind: TStr, Text: sb.String(), At: at})
		default:
			if i+1 < len(src) {
				if two := src[i : i+2]; two == "->" || two == ".." {
					adv()
					adv()
					toks = append(toks, Token{Kind: TPunct, Text: two, At: at})
					continue
				}
			}
			if strings.IndexByte("()[]{},:.!=|", c) >= 0 {
				adv()
				toks = append(toks, Token{Kind: TPunct, Text: string(c), At: at})
				continue
			}
			hint := ""
			if strings.IndexByte("+-*/<>&", c) >= 0 {
				hint = "GPLM has no operators; use calls like add(a, b), lt(a, b), and(a, b)"
			}
			return nil, Diag{At: at, Msg: fmt.Sprintf("unexpected character %q", c), Hint: hint}
		}
	}
	toks = append(toks, Token{Kind: TEOF, Text: "end of file", At: Pos{file, line, col}})
	return toks, nil
}
