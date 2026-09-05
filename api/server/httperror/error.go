package httperror

import "net/http"

// Error preserves a safe HTTP response while retaining the underlying
// failure for centralized logging and reporting. Expected rejections use normal
// response objects instead.
type Error struct {
	Cause      error
	Headers    http.Header
	Message    string
	StatusCode int
}

func (err *Error) Error() string { return err.Cause.Error() }
func (err *Error) Unwrap() error { return err.Cause }

func (err *Error) WriteResponse(w http.ResponseWriter) {
	for name, values := range err.Headers {
		w.Header()[name] = values
	}
	http.Error(w, err.Message, err.StatusCode)
}
