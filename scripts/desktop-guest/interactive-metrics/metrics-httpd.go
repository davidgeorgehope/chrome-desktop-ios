// Tiny static HTTP server for the interactive-metrics page.
// Listens on 127.0.0.1:8765, serves the sibling index.html, and
// writes POST /cgi-bin/report bodies to /dev/ttyS0 and a log file.
package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	root, err := filepath.Abs(filepath.Dir(os.Args[0]))
	if err != nil {
		root = "."
	}
	if len(os.Args) > 1 {
		root = os.Args[1]
	}
	logPath := "/tmp/interactive-metrics.log"
	tty, _ := os.OpenFile("/dev/ttyS0", os.O_WRONLY, 0)
	logf, _ := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	write := func(s string) {
		up := ""
		if b, err := os.ReadFile("/proc/uptime"); err == nil {
			up = strings.Fields(string(b))[0]
		}
		s = strings.TrimRight(s, "\n")
		s = fmt.Sprintf("%s %s up=%s\n", time.Now().UTC().Format("15:04:05"), s, up)
		b := []byte(s)
		if logf != nil {
			_, _ = logf.Write(b)
		}
		if tty != nil {
			_, _ = tty.Write(b)
		}
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" && r.URL.Path != "/index.html" {
			http.NotFound(w, r)
			return
		}
		http.ServeFile(w, r, filepath.Join(root, "index.html"))
	})
	report := func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		if r.Method == http.MethodPost {
			body, _ := io.ReadAll(io.LimitReader(r.Body, 4096))
			write(string(body))
			w.Header().Set("Content-Type", "text/plain")
			_, _ = io.WriteString(w, "ok\n")
			return
		}
		w.Header().Set("Content-Type", "text/plain")
		_, _ = io.WriteString(w, "ready\n")
	}
	mux.HandleFunc("/cgi-bin/report", report)
	mux.HandleFunc("/report", report)
	_ = http.ListenAndServe("127.0.0.1:8765", mux)
}
