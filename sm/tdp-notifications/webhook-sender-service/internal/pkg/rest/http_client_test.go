package rest

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"syscall"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	mocks "github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/app/mock"
	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/pkg/encryption"
)

func TestSendPostRequest(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name                   string
		serverHandler          http.HandlerFunc
		expectedCode           int
		expectedIsNetworkError bool
		expectedErr            bool
	}{
		{
			name: "Valid request, returns 200 OK",
			serverHandler: func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(http.StatusOK)
			},
			expectedCode:           http.StatusOK,
			expectedIsNetworkError: false,
			expectedErr:            false,
		},
		{
			name: "Server returns 500 Internal Server Error",
			serverHandler: func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(http.StatusInternalServerError)
			},
			expectedCode:           http.StatusInternalServerError,
			expectedIsNetworkError: false,
			expectedErr:            false,
		},
		{
			name: "Timeout error",
			serverHandler: func(w http.ResponseWriter, r *http.Request) {
				time.Sleep(2 * time.Second)
			},
			expectedCode:           0,
			expectedIsNetworkError: true,
			expectedErr:            true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			// Create a test server
			server := httptest.NewServer(tt.serverHandler)
			defer server.Close()

			// Create HTTPClient with timeout
			client := New(time.Second)

			// Send the request
			ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
			defer cancel()

			statusCode, err := client.SendPostRequest(ctx, server.URL, []byte(`{"test": "data"}`), "signature", uuid.NewString(), &mocks.MockLogger{})

			// Assertions
			if tt.expectedErr {
				assert.Error(t, err, "Expected an error but got nil")
				if tt.expectedIsNetworkError {
					assert.Equal(t, err, ErrNetwork)
				}
			} else {
				assert.NoError(t, err, "Expected no error but got one")
				assert.Equal(t, tt.expectedCode, statusCode, "Unexpected status code")
			}
		})
	}
}

func TestIsNetworkError(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		err      error
		expected bool
	}{
		{"Connection reset by peer (should retry)", syscall.ECONNRESET, true},
		{"Connection refused (should retry)", syscall.ECONNREFUSED, true},
		{"No route to host (should retry)", syscall.EHOSTUNREACH, true},
		{"Network unreachable (should retry)", syscall.ENETUNREACH, true},
		{"Timeout error (should retry)", &net.DNSError{IsTimeout: true}, true},
		{"Closed network connection (should retry)", net.ErrClosed, true},
		{"Generic error (should not retry)", errors.New("random error"), false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			result := isNetworkError(tt.err)
			assert.Equal(t, tt.expected, result, "Unexpected network error classification for test case: %s", tt.name)
		})
	}
}

func TestSetWebhookHeaders(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name          string
		eventID       string
		payload       []byte
		signedPayload string
		createdAt     time.Time
	}{
		{
			name:          "Valid payload and event ID",
			eventID:       "event-123",
			payload:       []byte("HelloWorld"),
			signedPayload: "hmac-signature-xyz",
			createdAt:     time.Date(2025, 3, 6, 12, 30, 45, 0, time.UTC),
		},
		{
			name:          "Empty payload",
			eventID:       "event-456",
			payload:       []byte(""),
			signedPayload: "hmac-signature-abc",
			createdAt:     time.Now().UTC(),
		},
		{
			name:          "Empty event ID",
			eventID:       "",
			payload:       []byte("TestPayload"),
			signedPayload: "hmac-signature-test",
			createdAt:     time.Now().UTC(),
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			req, _ := http.NewRequest(http.MethodPost, "https://example.com/webhook", nil)
			setWebhookHeaders(req, tc.eventID, tc.payload, tc.signedPayload, tc.createdAt)

			// Validate headers
			assert.Equal(t, "application/json", req.Header.Get("Content-Type"))
			assert.Equal(t, tc.signedPayload, req.Header.Get("HMAC-Signature"))
			assert.Equal(t, tc.createdAt.UTC().Format(time.RFC3339), req.Header.Get("Created-At"))
			assert.Equal(t, tc.eventID, req.Header.Get("Event-ID"))
			assert.Equal(t, encryption.GenerateIdempotencyKey(tc.payload), req.Header.Get("Idempotency-Key"))
		})
	}
}
