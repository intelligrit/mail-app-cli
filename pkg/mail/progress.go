package mail

import (
	"io"
	"strings"
)

// Preserve stderr for failures while forwarding complete progress lines. A
// process write may contain a partial line, or several lines at once.
type jxaProgressWriter struct {
	output   io.Writer
	progress func(string)
	pending  string
}

func (w *jxaProgressWriter) Write(p []byte) (int, error) {
	n, err := w.output.Write(p)
	if w.progress != nil {
		w.pending += string(p[:n])
		for {
			line, rest, found := strings.Cut(w.pending, "\n")
			if !found {
				break
			}
			w.pending = rest
			if text, ok := strings.CutPrefix(line, "mail-app-progress: "); ok {
				w.progress(strings.TrimSuffix(text, "\r"))
			}
		}
	}
	return n, err
}
