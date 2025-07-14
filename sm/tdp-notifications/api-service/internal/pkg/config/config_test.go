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
        queueName: otherQueue
        hostname: rmq-host
        port: 5671
        username: rmq-user
        password: pass
        exchange: rmq-test
    `
	tmpfile, err := os.Create(filepath.Join(os.TempDir(), "dev.yaml"))
	assert.Nil(t, err, "Error creating temporary file")
	defer os.Remove(tmpfile.Name())
	_, err = tmpfile.WriteString(content)
	assert.Nil(t, err, "Error writing to temporary file")
	tmpfile.Close()

	config, err := LoadConfiguration(os.TempDir())
	assert.Nil(t, err, "Error loading configuration")

	assert.Equal(t, "1234", config.ServicePort)
	assert.Equal(t, 10, config.HealthCheck.Frequency)
	assert.Equal(t, 5, config.HealthCheck.Latency)
	assert.Equal(t, 3, config.HealthCheck.Timeout)
	assert.Equal(t, "buffer", config.Log.OutputSink)
	assert.Equal(t, "debug", config.Log.LogLevel)
	assert.Equal(t, "otherQueue", config.RMQ.QueueName)
	assert.Equal(t, "rmq-host", config.RMQ.HostName)
	assert.Equal(t, 5671, config.RMQ.Port)
	assert.Equal(t, "rmq-user", config.RMQ.Username)
	assert.Equal(t, "pass", config.RMQ.Password)
	assert.Equal(t, "rmq-test", config.RMQ.Exchange)
}

func TestLoadConfigurationNonExistingFile(t *testing.T) {
	config, err := LoadConfiguration("non_existing_dir")
	assert.NotNil(t, err, "Expected error when loading non-existing file")

	// Ensure the error message contains the specific text
	assert.Contains(t, err.Error(), "cannot read configuration file", "Expected error message to contain 'cannot read configuration file'")

	defaultLogConfig := zap.LoggerConfig{
		Environment: "development",
		OutputSink:  "stderr",
	}
	require.Equal(t, defaultLogConfig, config.Log)
}

func TestLoadConfigurationInvalidYAML(t *testing.T) {
	// Create a temporary file with an invalid YAML configuration
	content := `
    servicePort: 1234
    healthCheck:
        frequency: not_an_integer   # Invalid type to cause unmarshal failure
    log:
        outputSink: buffer
    rmq:
        queueName: otherQueue
        hostname: rmq-host
        port: 5671
        username: rmq-user
        password: pass
        exchange: rmq-test
    `
	tmpfile, err := os.Create(filepath.Join(os.TempDir(), "dev.yaml"))
	assert.Nil(t, err, "Error creating temporary file")
	defer os.Remove(tmpfile.Name())
	_, err = tmpfile.WriteString(content)
	assert.Nil(t, err, "Error writing to temporary file")
	tmpfile.Close()

	_, err = LoadConfiguration(os.TempDir())
	assert.NotNil(t, err, "Expected error while decoding invalid YAML configuration")
	assert.Contains(t, err.Error(), "unable to decode configuration", "Expected 'unable to decode configuration' error message")
}

func TestLoadConfigurationValidationFailure(t *testing.T) {
	// Create a temporary file with a YAML configuration that is missing a required field (ServicePort)
	content := `
    healthCheck:
        frequency: 10
        latency: 5
        timeout: 3
    log:
        outputSink: buffer
    rmq:
        queueName: otherQueue
        hostname: rmq-host
        port: 5671
        username: rmq-user
        password: pass
        exchange: rmq-test
    `
	tmpfile, err := os.Create(filepath.Join(os.TempDir(), "dev.yaml"))
	assert.Nil(t, err, "Error creating temporary file")
	defer os.Remove(tmpfile.Name())
	_, err = tmpfile.WriteString(content)
	assert.Nil(t, err, "Error writing to temporary file")
	tmpfile.Close()

	_, err = LoadConfiguration(os.TempDir())
	assert.NotNil(t, err, "Expected error due to validation failure")
	assert.Contains(t, err.Error(), "error validating configuration", "Expected 'error validating configuration' error message")
}

func TestRMQProtocol(t *testing.T) {
	mockConfig := Config{}

	tests := []struct {
		tls_enabled bool
		protocol    string
	}{
		{
			tls_enabled: true,
			protocol:    AMQPS,
		},
		{
			tls_enabled: false,
			protocol:    AMQP,
		},
	}
	for _, test := range tests {
		mockConfig.RMQ.TLSEnabled = test.tls_enabled
		protocol := mockConfig.RMQprotocol()
		assert.Equal(t, test.protocol, protocol, "Expected '%s' when TLSEnabled is %t", test.protocol, test.tls_enabled)
	}
}

func TestRMQUrl(t *testing.T) {
	// Define a mock config
	mockConfig := Config{
		RMQ: struct {
			HostName         string `yaml:"hostname" validate:"required"`
			Port             int    `yaml:"port" validate:"required"`
			Username         string `yaml:"username" validate:"required"`
			Password         string `yaml:"password" validate:"required"`
			Exchange         string `yaml:"exchange" validate:"required"`
			QueueType        string `yaml:"queueType"`
			QueueName        string `yaml:"queueName"`
			Readers          int    `yaml:"readers"`
			TLSEnabled       bool   `yaml:"tlsEnabled"`
			TLSSkipVerify    bool   `yaml:"tlsSkipVerify"`
			CertFile         string `yaml:"certFile"`
			KeyFile          string `yaml:"keyFile"`
			CAFile           string `yaml:"caFile"`
			VerifyServerName string `yaml:"verifyServerName"`
		}{
			HostName:   "rmq-host",
			Port:       5671,
			Username:   "rmq-user",
			Password:   "rmq-pass",
			Exchange:   "test-exchange",
			TLSEnabled: true, // Test case where TLS is enabled
		},
	}
	// Test case where TLS is enabled
	expectedURLTLS := "amqps://rmq-user:rmq-pass@rmq-host:5671"
	assert.Equal(t, expectedURLTLS, mockConfig.RMQurl(), "Expected correct RabbitMQ URL with TLS")

	// Test case where TLS is disabled
	mockConfig.RMQ.TLSEnabled = false
	expectedURLNonTLS := "amqp://rmq-user:rmq-pass@rmq-host:5671"
	assert.Equal(t, expectedURLNonTLS, mockConfig.RMQurl(), "Expected correct RabbitMQ URL without TLS")

	// Test case with a different port
	mockConfig.RMQ.Port = 5672
	expectedURLDifferentPort := "amqp://rmq-user:rmq-pass@rmq-host:5672"
	assert.Equal(t, expectedURLDifferentPort, mockConfig.RMQurl(), "Expected correct RabbitMQ URL with different port")

	// Test case with a different hostname
	mockConfig.RMQ.HostName = "another-host"
	expectedURLDifferentHost := "amqp://rmq-user:rmq-pass@another-host:5672"
	assert.Equal(t, expectedURLDifferentHost, mockConfig.RMQurl(), "Expected correct RabbitMQ URL with different hostname")
}
