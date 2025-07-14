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
		filename       string
		expectedConfig Config
		requireErr     require.ErrorAssertionFunc
	}{
		{
			name:       "Error - Missing Config File",
			filename:   "non_existent_file",
			requireErr: require.Error,
		},
		{
			name:     "Error - Decoding Failure (Wrong Types)",
			filename: "dev",
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
			requireErr: require.Error,
			expectedConfig: Config{ // default values
				Log: zap.LoggerConfig{
					OutputSink: "buffer",
					LogLevel:   "debug",
				},
				RMQ: RMQ{
					HostName: "rmq-host",
					Username: "rmq-user",
					Password: "pass",
					Exchange: "rmq-test",
				},
				SMTPServer: SMTPServer{
					RetryAttempts: 3,
					RetryMaxDelay: time.Second,
				},
			},
		},
		{
			name:     "Error - Validation Failure (Missing Required Fields)",
			filename: "dev",
			content: `log:
  outputSink: buffer
  logLevel: debug
rmq:
  port: 5671
  username: rmq-user
  password: pass`, // Missing "hostname" and "exchange"
			requireErr: require.Error,
			expectedConfig: Config{ // default values
				Log: zap.LoggerConfig{
					OutputSink:   "buffer",
					LogLevel:     "debug",
					RedactValues: []string{"pass", ""},
				},
				RMQ: RMQ{
					Username: "rmq-user",
					Password: "pass",
					Port:     5671,
				},
				SMTPServer: SMTPServer{
					RetryAttempts: 3,
					RetryMaxDelay: time.Second,
				},
			},
		},
		{
			name:     "Success - Valid Config",
			filename: "dev",
			content: `log:
  outputSink: buffer
  logLevel: debug
rmq:
  hostname: rmq-host
  port: 5671
  username: rmq-user
  password: rmq-pass
  exchange: rmq-test
  exchangeKind: direct
  exchangeDurable: true
  queueType: classic
  emailSendQueue: 
    name: email_send_queue
  finalStatusQueue: 
    name: final_status_notification
  tlsEnabled: true
  tlsSkipVerify: true
smtpServer:
  host: smtp.gmail.com
  port: 587
  username: user-smtp
  password: pass-smtp`,
			requireErr: require.NoError,
			expectedConfig: Config{
				Log: zap.LoggerConfig{
					OutputSink:   "buffer",
					LogLevel:     "debug",
					RedactValues: []string{"rmq-pass", "pass-smtp"},
				},
				RMQ: RMQ{
					HostName:        "rmq-host",
					Port:            5671,
					Username:        "rmq-user",
					Password:        "rmq-pass",
					Exchange:        "rmq-test",
					ExchangeKind:    "direct",
					QueueType:       "classic",
					ExchangeDurable: true,
					EmailSendQueue: Queue{
						Name: "email_send_queue",
					},
					FinalStatusQueue: Queue{
						Name: "final_status_notification",
					},
					TLSEnabled:    true,
					TLSSkipVerify: true,
				},
				SMTPServer: SMTPServer{
					Host:          "smtp.gmail.com",
					Port:          "587",
					Username:      "user-smtp",
					Password:      "pass-smtp",
					RetryAttempts: 3,
					RetryMaxDelay: time.Second,
				},
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			configDir := os.TempDir()
			configFile, err := os.Create(filepath.Join(configDir, tc.filename))
			require.NoError(t, err, "Failed to create temp config file")
			defer func() {
				assert.NoError(t, configFile.Close())
				assert.NoError(t, os.Remove(configFile.Name()))
			}()
			_, err = configFile.WriteString(tc.content)
			require.NoError(t, err, "Failed to write to temp config file")

			config, err := LoadConfiguration(configDir)
			tc.requireErr(t, err)
			require.Equal(t, tc.expectedConfig, config)
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
