package mail

import (
	"bytes"
	"reflect"
	"runtime"
	"testing"
)

func TestJXAProgressSplitWrites(t *testing.T) {
	var stderr bytes.Buffer
	var stages []string
	w := jxaProgressWriter{output: &stderr, progress: func(s string) { stages = append(stages, s) }}
	for _, chunk := range []string{"mail-app-pro", "gress: Selecting 3 messages\nwarning\nmail-app-progress: Verifying", " 3 messages\r\n"} {
		if _, err := w.Write([]byte(chunk)); err != nil {
			t.Fatal(err)
		}
	}
	if !reflect.DeepEqual(stages, []string{"Selecting 3 messages", "Verifying 3 messages"}) {
		t.Fatalf("unexpected stages: %q", stages)
	}
	if !bytes.Contains(stderr.Bytes(), []byte("warning")) {
		t.Fatal("lost diagnostic stderr")
	}
}

func TestJXAStreamsProgressWithoutContaminatingJSON(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("JXA requires macOS")
	}
	var stages []string
	client := &Client{Progress: func(s string) { stages = append(stages, s) }}
	// Defines functions but never calls Mail or Accessibility.
	output, err := client.runJXA(jsNativeArchive + `archiveProgress('Verifying 3 messages'); JSON.stringify({ok:3});`)
	if err != nil {
		t.Fatal(err)
	}
	if output != `{"ok":3}` || !reflect.DeepEqual(stages, []string{"Verifying 3 messages"}) {
		t.Fatalf("output=%q stages=%q", output, stages)
	}
}
