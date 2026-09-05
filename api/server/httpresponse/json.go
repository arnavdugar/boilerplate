// Package httpresponse writes pre-encoded API responses.
package httpresponse

import "net/http"

// JSON holds the exact serialized bytes returned by an idempotent write or replay.
// A nil Body represents a rejection with no response body.
type JSON struct {
	Body   []byte
	Status int
}

// Write preserves the stored body without decoding or re-encoding it.
// Write failures are returned to the server's shared error handler.
func (r JSON) Write(w http.ResponseWriter) error {
	if r.Body == nil {
		w.WriteHeader(r.Status)
		return nil
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(r.Status)
	_, err := w.Write(r.Body)
	return err
}
