package encryption

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
)

// SignPayload generates an HMAC-SHA256 signature for the payload using the given secret
func SignPayload(payload []byte, secret string) string {
	hmac := hmac.New(sha256.New, []byte(secret))
	hmac.Write(payload)
	return hex.EncodeToString(hmac.Sum(nil))
}

// GenerateIdempotencyKey generates a SHA256 hash of the notification payload
func GenerateIdempotencyKey(payload []byte) string {
	hash := sha256.Sum256(payload)
	return hex.EncodeToString(hash[:])
}
