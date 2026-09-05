package httpresponse

import (
	"errors"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestJSONWritePreservesStoredBytes(t *testing.T) {
	for _, tc := range []struct {
		body        []byte
		contentType string
		name        string
		status      int
	}{{
		body:        []byte(" {\"id\": 123, \"amount\": 1.00}\n"),
		contentType: "application/json",
		name:        "serialized response",
		status:      201,
	}, {
		body:        []byte{},
		contentType: "application/json",
		name:        "empty serialized body",
		status:      200,
	}, {
		name:   "rejection without body",
		status: 409,
	}} {
		t.Run(tc.name, func(t *testing.T) {
			recorder := httptest.NewRecorder()
			response := JSON{
				Body:   tc.body,
				Status: tc.status,
			}

			err := response.Write(recorder)

			require.NoError(t, err)
			assert.Equal(t, tc.status, recorder.Code)
			assert.Equal(t, tc.contentType, recorder.Header().Get("Content-Type"))
			assert.Equal(t, string(tc.body), recorder.Body.String())
		})
	}
}

func TestJSONWriteReturnsTransportFailure(t *testing.T) {
	failure := errors.New("connection closed")
	writer := failingWriter{
		ResponseRecorder: httptest.NewRecorder(),
		err:              failure,
	}
	response := JSON{
		Body:   []byte(`{"id":123}`),
		Status: 201,
	}

	err := response.Write(writer)

	assert.ErrorIs(t, err, failure)
	assert.Equal(t, 201, writer.Code)
	assert.Empty(t, writer.Body.String())
}

type failingWriter struct {
	*httptest.ResponseRecorder
	err error
}

func (w failingWriter) Write([]byte) (int, error) { return 0, w.err }
