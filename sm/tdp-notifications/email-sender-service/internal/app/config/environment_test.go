package config

import (
	"github.com/stretchr/testify/require"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestGetEnvironment(t *testing.T) {
	testCases := []struct {
		name        string
		envVar      string
		expectedEnv Environment
	}{
		{"Default to Dev", "", Dev},
		{"Explicit Prod", "prod", Prod},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			os.Setenv("ENV", tc.envVar)

			require.Equal(t, tc.expectedEnv, GetEnvironment())

			// Cleanup
			os.Unsetenv("ENV")
		})
	}
}

// ✅ Test Environment String Representation
func TestEnvironmentString(t *testing.T) {
	t.Parallel()
	testCases := []struct {
		name     string
		env      Environment
		expected string
	}{
		{"Dev String", Dev, "dev"},
		{"Prod String", Prod, "prod"},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			assert.Equal(t, tc.expected, tc.env.String())
		})
	}
}

// ✅ Test Environment Logging Levels
func TestEnvironmentLoggingEnv(t *testing.T) {
	t.Parallel()
	testCases := []struct {
		name     string
		env      Environment
		expected string
	}{
		{"Development Logging", Dev, "development"},
		{"Production Logging", Prod, "production"},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			assert.Equal(t, tc.expected, tc.env.LoggingEnv())
		})
	}
}
