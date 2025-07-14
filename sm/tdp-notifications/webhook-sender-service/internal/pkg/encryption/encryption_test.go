package encryption

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSignPayload(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name        string
		payload     []byte
		secret      string
		expectError bool
		expected    string
	}{
		{
			name:        "Valid payload and secret",
			payload:     []byte("HelloWorld"),
			secret:      "1e3bc892f382fc860aff3ce0562cd0eb80deb06a740b92036b91080d6f68539f",
			expectError: false,
			// Precomputed HMAC-SHA256 using an https://www.freeformatter.com/hmac-generator.html#before-output
			expected: "2caee088592cf6bd4a7db2ca6577fa80537f63c3e5225d5d2f88a3bdc873aa9b",
		},
		{
			name:        "Empty payload",
			payload:     []byte(""),
			secret:      "1e3bc892f382fc860aff3ce0562cd0eb80deb06a740b92036b91080d6f68539f",
			expectError: false,
			expected:    "3fa6fa831fcca931e218ae839836855b1d0446a198a80f97d26d543fcc706877",
		},
		{
			name:        "Empty secret",
			payload:     []byte("HelloWorld"),
			secret:      "",
			expectError: false,
			expected:    "a77d3694491c2109157bc896a06b5eb92eb1510b6d8c5ed8932da221c022aa0e",
		},
		{
			name:        "Both payload and secret empty",
			payload:     []byte(""),
			secret:      "",
			expectError: false,
			expected:    "b613679a0814d9ec772f95d778c35fc5ff1697c493715653c6c712144292c5ad",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			signature := SignPayload(tc.payload, tc.secret)

			assert.Equal(t, tc.expected, signature)

		})
	}
}

func TestGenerateIdempotencyKey(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		payload  []byte
		expected string
	}{
		{
			name:     "Valid payload",
			payload:  []byte("HelloWorld"),
			expected: "872e4e50ce9990d8b041330c47c9ddd11bec6b503ae9386a99da8584e9bb12c4",
		},
		{
			name:     "Empty payload",
			payload:  []byte(""),
			expected: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", // SHA256 of empty string
		},
		{
			name:     "Short payload",
			payload:  []byte("test"),
			expected: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
		},
		{
			name:     "Long payload",
			payload:  []byte("This is a longer payload to check the hash consistency."),
			expected: "b71e7caf398dedcd6d8078b930c97c5300b4bea9f4e7570f82a8faea3737fc6f",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			idempotencyKey := GenerateIdempotencyKey(tc.payload)
			assert.Equal(t, tc.expected, idempotencyKey)
		})
	}
}
