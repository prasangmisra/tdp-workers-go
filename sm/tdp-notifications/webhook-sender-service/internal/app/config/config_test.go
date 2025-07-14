package config

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
)

// ✅ Test LoadConfiguration with different cases
func TestLoadConfiguration(t *testing.T) {
	testCases := []struct {
		name           string
		content        string
		expectedErr    string
		expectedConfig Config
	}{
		{
			name:        "Error - Missing Config File",
			content:     "",
			expectedErr: "cannot read configuration file",
		},
		{
			name: "Error - Decoding Failure (Wrong Types)",
			content: `log:
  outputSink: buffer
  logLevel: debug
rmq:
  hostname: rmq-host
  port: "not-an-integer"   # WRONG TYPE: Should be int, but is a string
  username: rmq-user
  password: pass
  exchange: rmq-test
  maxRetries: "five"       # WRONG TYPE: Should be int, but is a string`,
			expectedErr: "unable to decode configuration",
		},
		{
			name: "Error - Validation Failure (Missing Required Fields)",
			content: `log:
  outputSink: buffer
  logLevel: debug
rmq:
  port: 5671
  username: rmq-user
  password: pass`, // Missing "hostname" and "exchange"
			expectedErr: "error validating configuration",
		},
		{
			name: "Success - Valid Config",
			content: `log:
  outputSink: buffer
  logLevel: debug
http:
  timeout: 10s
rmq:
  hostname: rmq-host
  port: 5671
  username: rmq-user
  password: pass
  exchange: rmq-test
  exchangekind: direct
  queueType: classic
  exchangeDurable: true
  notificationwebhookDLExchange: notification_webhook_dlx
  webhookSendQueue: 
    name: notification_webhook
    maxpriority: 1
  finalStatusQueue: 
    name: final_status_notification
  retryQueuesConfig:
    retryIntervals:
      - 300 # 5 minutes before retry
      - 3600 # 1 hour before retry
      - 21600 # 6 hours before retry
    maxpriority: 1`,
			expectedErr: "",
			expectedConfig: Config{
				Log: zap.LoggerConfig{
					OutputSink:   "buffer",
					LogLevel:     "debug",
					RedactValues: []string{"pass"},
				},
				HTTP: HTTP{
					Timeout: 10 * time.Second,
				},
				RMQ: RMQ{
					HostName:                      "rmq-host",
					Port:                          5671,
					Username:                      "rmq-user",
					Password:                      "pass",
					Exchange:                      "rmq-test",
					ExchangeKind:                  "direct",
					QueueType:                     "classic",
					ExchangeDurable:               true,
					NotificationwebhookDLExchange: "notification_webhook_dlx",
					WebhookSendQueue: PriorityQueue{
						Name:        "notification_webhook",
						MaxPriority: 1,
					},
					FinalStatusQueue: Queue{Name: "final_status_notification"},
					RetryQueuesConfig: RetryQueuesConfig{
						RetryIntervals: []int{300, 3600, 21600},
						MaxPriority:    1,
					},
					RetryQueues: []RetryQueue{
						{
							Name: "notification_webhook_retry_1",
							TTL:  300,
						},
						{
							Name: "notification_webhook_retry_2",
							TTL:  3600,
						},
						{
							Name: "notification_webhook_retry_3",
							TTL:  21600,
						},
					},
				},
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.name == "Error - Missing Config File" {
				// Ensure function fails when config file is missing
				nonExistentDir := filepath.Join(os.TempDir(), "non_existent_dir")
				_, err := LoadConfiguration(nonExistentDir)
				require.Error(t, err)
				assert.Contains(t, err.Error(), tc.expectedErr)
				return
			}

			tmpfile, err := os.Create(filepath.Join(os.TempDir(), "dev"))
			require.NoError(t, err, "Failed to create temp config file")
			defer os.Remove(tmpfile.Name())

			if tc.content != "" {
				_, err = tmpfile.WriteString(tc.content)
				require.NoError(t, err, "Failed to write to temp config file")
				tmpfile.Close()
			}

			config, err := LoadConfiguration(os.TempDir())

			if tc.expectedErr != "" {
				require.Error(t, err)
				assert.Contains(t, err.Error(), tc.expectedErr)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tc.expectedConfig, config)

			}
		})
	}

}

// ✅ Test RMQ URL generation with different TLS settings
func TestRMQurl(t *testing.T) {
	t.Parallel()
	testCases := []struct {
		name      string
		tlsEnable bool
		expected  string
	}{
		{"AMQP URL", false, "amqp://rmq-user:rmq-pass@rmq-host:5672"},
		{"AMQPS URL with TLS", true, "amqps://rmq-user:rmq-pass@rmq-host:5672"},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			cfg := Config{
				RMQ: RMQ{
					HostName:   "rmq-host",
					Port:       5672,
					Username:   "rmq-user",
					Password:   "rmq-pass",
					TLSEnabled: tc.tlsEnable,
				},
			}
			assert.Equal(t, tc.expected, cfg.RMQurl())
		})
	}
}

// ✅ Test Environment Detection
func TestGetEnvironment(t *testing.T) {
	t.Parallel()
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
			t.Parallel()
			if tc.envVar == "" {
				os.Unsetenv("ENV")
			} else {
				os.Setenv("ENV", tc.envVar)
			}

			assert.Equal(t, tc.expectedEnv, GetEnvironment())

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
