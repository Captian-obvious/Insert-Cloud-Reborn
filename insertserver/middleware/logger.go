// middleware package borrowed from random prod app
package middleware

import (
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type responseWriter struct {
	http.ResponseWriter
	status      int
	size        int
	wroteHeader bool
}

func (rw *responseWriter) WriteHeader(statusCode int) {
	if !rw.wroteHeader {
		rw.status = statusCode
		rw.wroteHeader = true
		rw.ResponseWriter.WriteHeader(statusCode)
	}
}
func (rw *responseWriter) Write(b []byte) (int, error) {
	if !rw.wroteHeader {
		rw.WriteHeader(http.StatusOK)
	}
	size, err := rw.ResponseWriter.Write(b)
	rw.size += size
	return size, err
}
func (rw *responseWriter) Status() int {
	return rw.status
}
func (rw *responseWriter) Size() int {
	return rw.size
}
func formatQuery(query string) string {
	if query == "" {
		return ""
	}
	return sanitizeQuery("?" + query)
}
func sanitizeQuery(raw string) string {
	u, err := url.Parse(raw)
	if err != nil {
		return raw
	}
	q := u.Query()
	for key := range q {
		if strings.Contains(strings.ToLower(key), "token") {
			q.Set(key, "[REDACTED]")
		}
	}
	u.RawQuery = q.Encode()
	return u.String()
}
func LoggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := &responseWriter{ResponseWriter: w, status: 200}
		start := time.Now()

		next.ServeHTTP(rec, r)

		log.Printf("%s %s%s %d %d \"%s\" \"%s\" \"responseTime=%s\"",
			r.Method,
			r.URL.Path,
			formatQuery(r.URL.RawQuery),
			rec.status,
			rec.Size(),
			r.UserAgent(),
			r.RemoteAddr,
			time.Since(start),
		)
	})
}
