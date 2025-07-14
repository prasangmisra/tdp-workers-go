package rest

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"syscall"
	"time"

	"github.com/tucowsinc/tdp-notifications/webhook-sender-service/internal/pkg/encryption"
	"github.com/tucowsinc/tdp-shared-go/logger"
	restClient "github.com/tucowsinc/tdp-shared-go/rest"
)

var ErrNetwork = errors.New("network error")

// HTTPClient defines an interface for making HTTP requests
//
//go:generate mockery --name IHTTPClient --output ../../app/mock --outpkg mock
type IHTTPClient interface {
	SendPostRequest(ctx context.Context, url string, payload []byte, signedPayload string, requestID string, log logger.ILogger) (int, error)
}

// HTTPClient implements HTTPClient
type HTTPClient struct {
	Client *restClient.Client
}

// New initializes an HTTPClient with a configurable timeout
func New(timeout time.Duration) *HTTPClient {
	return &HTTPClient{
		Client: restClient.NewClient(restClient.WithTimeout(timeout)),
	}
}

// SendPostRequest sends a signed POST request and returns status code & error
func (h *HTTPClient) SendPostRequest(ctx context.Context, url string, payload []byte, signedPayload string, requestID string, log logger.ILogger) (int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewBuffer([]byte(payload)))
	if err != nil {
		return 0, fmt.Errorf("failed to create request: %w", err)
	}

	// Set headers
	setWebhookHeaders(req, requestID, payload, signedPayload, time.Now())
	resp, err := h.Client.GetClient().Do(req)
	if err != nil {
		if isNetworkError(err) {
			return 0, ErrNetwork
		}
		return 0, err
	}
	defer resp.Body.Close()

	return resp.StatusCode, nil
}

// isNetworkError checks if an error is related to network issues
func isNetworkError(err error) bool {
	var netErr net.Error
	if errors.As(err, &netErr) && netErr.Timeout() {
		return true
	}

	// Check for common network-related errors
	if errors.Is(err, net.ErrClosed) {
		return true
	}

	// Check for system-level errors that indicate a network issue
	switch {
	case errors.Is(err, syscall.ECONNRESET), // Connection reset by peer
		errors.Is(err, syscall.ECONNREFUSED), // Connection refused
		errors.Is(err, syscall.EHOSTUNREACH), // No route to host
		errors.Is(err, syscall.ENETUNREACH),  // Network is unreachable
		errors.Is(err, syscall.ETIMEDOUT):    // Connection timed out
		return true
	}

	return false
}

func setWebhookHeaders(req *http.Request, eventID string, payload []byte, signedPayload string, createdAt time.Time) {
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("HMAC-Signature", signedPayload)                               // Ensures integrity & authenticity
	req.Header.Set("Created-At", createdAt.UTC().Format(time.RFC3339))            // Timestamp in UTC format
	req.Header.Set("Event-ID", eventID)                                           // Unique event ID
	req.Header.Set("Idempotency-Key", encryption.GenerateIdempotencyKey(payload)) // Ensures deduplication
}
