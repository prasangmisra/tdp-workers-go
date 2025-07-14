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
        webhookQueue:
            queueName: webhook_notification
        emailQueue:
            queueName: email_send
        hostname: rmq-host
        port: 5671
        username: rmq-user
        password: pass
        exchange: rmq-test
    domainsdb:
        hostname: localhost
        port: 7654
        username: user
        password: pass
        dbname: domainsdb
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

	assert.Equal(t, 10, config.HealthCheck.Frequency)
	assert.Equal(t, 5, config.HealthCheck.Latency)
	assert.Equal(t, 3, config.HealthCheck.Timeout)
	assert.Equal(t, "webhook_notification", config.RMQ.WebhookQueue.QueueName)
	assert.Equal(t, "email_send", config.RMQ.EmailQueue.QueueName)
	assert.Equal(t, "rmq-host", config.RMQ.HostName)
	assert.Equal(t, 5671, config.RMQ.Port)
	assert.Equal(t, "rmq-user", config.RMQ.Username)
	assert.Equal(t, "pass", config.RMQ.Password)
	assert.Equal(t, "rmq-test", config.RMQ.Exchange)
	assert.Equal(t, "buffer", config.Log.OutputSink)
	assert.Equal(t, "debug", config.Log.LogLevel)
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
        webhookQueue:
            queueName: webhook_notification
        emailQueue:
            queueName: email_response_notification
    domainsdb:
        hostname: localhost
        port: 7654
        username: user
        password: pass
        dbname: domainsdb
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

	assert.Equal(t, 30, config.HealthCheck.Frequency)
	assert.Equal(t, 3, config.HealthCheck.Latency)
	assert.Equal(t, 5, config.HealthCheck.Timeout)
	assert.Equal(t, "rmq-host", config.RMQ.HostName)
	assert.Equal(t, 5671, config.RMQ.Port)
	assert.Equal(t, "rmq-user", config.RMQ.Username)
	assert.Equal(t, "pass", config.RMQ.Password)
	assert.Equal(t, "rmq-test", config.RMQ.Exchange)
	assert.Equal(t, "stderr", config.Log.OutputSink)
}

func TestLoadConfigurationNonExistingFile(t *testing.T) {
	config, err := LoadConfiguration("non_existing_dir")
	assert.NotNil(t, err, "Expected error when loading non-existing file")
	defaultLogConfig := zap.LoggerConfig{
		Environment: "development",
		OutputSink:  "stderr",
	}
	require.Equal(t, defaultLogConfig, config.Log)
}
