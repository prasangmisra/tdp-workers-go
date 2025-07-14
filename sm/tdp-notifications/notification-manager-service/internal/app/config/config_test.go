//go:build integration

package config

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"

	"github.com/stretchr/testify/assert"
)

func TestLoadConfiguration(t *testing.T) {
	// Create a temporary file with the mocked configuration
	content := `
    servicePort: 1234
    healthCheck:
        frequency: 10
        latency: 5
        timeout: 3
    log:
        outputSink: buffer
        logLevel: debug
    rmq:
        hostname: rmq-host
        port: 5671
        finalstatusqueue:
          name: otherQueue
        emailrenderingqueue:
          name: emailRenderingQueue
        emailnotificationqueue:
          name: emailNotificationQueue  
        username: rmq-user
        password: pass
        exchange: rmq-test
    subscriptiondb:
        hostname: localhost
        port: 7654
        username: user
        password: pass
        dbname: subscriptiondb
    `
	tmpfile, err := os.Create(filepath.Join(os.TempDir(), "dev.yaml"))
	assert.Nil(t, err, "Error creating temporary file")
	defer os.Remove(tmpfile.Name())
	_, err = tmpfile.WriteString(content)
	assert.Nil(t, err, "Error writing to temporary file")
	tmpfile.Close()

	config, err := LoadConfiguration(os.TempDir())
	assert.Nil(t, err, "Error loading configuration")

	expected_config := Config{
		Log: zap.LoggerConfig{
			Environment:  "development",
			OutputSink:   "buffer",
			LogLevel:     "debug",
			RedactValues: []string{"pass", "pass"},
		},

		HealthCheck: struct {
			Frequency int `yaml:"frequency"`
			Latency   int `yaml:"latency"`
			Timeout   int `yaml:"timeout"`
		}{
			Frequency: 10,
			Latency:   5,
			Timeout:   3,
		},

		RMQ: RMQ{
			HostName: "rmq-host",
			Port:     5671,
			Username: "rmq-user",
			Password: "pass",
			Exchange: "rmq-test",
			FinalStatusQueue: Queue{
				Name: "otherQueue",
			},
			EmailRenderingQueue: Queue{
				Name: "emailRenderingQueue",
			},
			EmailNotificationQueue: Queue{
				Name: "emailNotificationQueue",
			},
		},
		SubscriptionDB: Database{
			HostName: "localhost",
			Port:     7654,
			Username: "user",
			Password: "pass",
			DBName:   "subscriptiondb",
		},
	}

	assert.Equal(t, expected_config, config)
}

func TestLoadConfigurationDefaults(t *testing.T) {
	tmpfile, err := os.Create(filepath.Join(os.TempDir(), "dev.yaml"))
	assert.Nil(t, err, "Error creating temporary file")
	defer os.Remove(tmpfile.Name())
	// Create a temporary file with the mocked configuration
	content := `
    servicePort: 1234
    rmq:
        hostname: rmq-host
        port: 5671
        username: rmq-user
        password: pass
        exchange: rmq-test
        finalstatusqueue:
          name: statusnotification
        emailrenderingqueue:
          name: emailRenderingQueue
        emailnotificationqueue:
          name: emailNotificationQueue
    subscriptiondb:
        hostname: localhost
        port: 7654
        username: user
        password: pass
        dbname: subscriptiondb
    `
	_, err = tmpfile.WriteString(content)
	assert.Nil(t, err, "Error writing to temporary file")
	tmpfile.Close()

	config, err := LoadConfiguration(os.TempDir())
	assert.Nil(t, err, "Error loading configuration")

	expected_config := Config{
		Log: zap.LoggerConfig{
			Environment:  "development",
			OutputSink:   "stderr",
			RedactValues: []string{"pass", "pass"},
		},

		HealthCheck: struct {
			Frequency int `yaml:"frequency"`
			Latency   int `yaml:"latency"`
			Timeout   int `yaml:"timeout"`
		}{
			Frequency: 30,
			Latency:   3,
			Timeout:   5,
		},

		RMQ: RMQ{
			HostName: "rmq-host",
			Port:     5671,
			Username: "rmq-user",
			Password: "pass",
			Exchange: "rmq-test",
			FinalStatusQueue: Queue{
				Name: "statusnotification",
			},
			EmailRenderingQueue: Queue{
				Name: "emailRenderingQueue",
			},
			EmailNotificationQueue: Queue{
				Name: "emailNotificationQueue",
			},
		},

		SubscriptionDB: Database{
			HostName: "localhost",
			Port:     7654,
			Username: "user",
			Password: "pass",
			DBName:   "subscriptiondb",
		},
	}

	assert.Equal(t, expected_config, config)
}

func TestLoadConfigurationNonExistingFile(t *testing.T) {
	config, err := LoadConfiguration("non_existing_dir")
	assert.NotNil(t, err, "Expected error when loading non-existing file")
	defaultLogConfig := zap.LoggerConfig{
		Environment:  "development",
		OutputSink:   "stderr",
		RedactValues: nil,
	}
	require.Equal(t, defaultLogConfig, config.Log)
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
