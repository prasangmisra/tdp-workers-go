package config

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestLoadConfiguration(t *testing.T) {
	config, err := LoadConfiguration("../../.env")
	assert.Nil(t, err, "Error loading configuration")
	assert.Equal(t, "domains", config.RmqUserName)
	assert.Equal(t, "test", config.RmqExchangeName)
	assert.Equal(t, "", config.RmqQueueName)

	redactValues, _ := config.GetRedactValues()
	assert.Len(t, redactValues, 2)
}

func TestGetRedactValues(t *testing.T) {
	config := Config{
		DBPass:           "dbpass",
		RmqPassword:      "pass",
		AWSHostingApiKey: "apikey",
	}
	redactValues, err := config.GetRedactValues()
	assert.Nil(t, err, "Error getting redact values")
	assert.Equal(t, []string{"pass", "dbpass", "apikey"}, redactValues)
}

func TestRmqUrl(t *testing.T) {
	config := Config{
		RmqUserName: "user",
		RmqPassword: "pass",
		RmqHostName: "localhost",
		RmqPort:     5672,
	}

	expectedUrl := "amqp://user:pass@localhost:5672"
	assert.Equal(t, expectedUrl, config.RmqUrl())

}

func TestDatabaseUrl(t *testing.T) {
	config := Config{
		DBUser: "user",
		DBPass: "pass",
		DBHost: "localhost",
		DBPort: 5672,
		DBName: "test",
	}
	expectedUrl := "postgres://user:pass@localhost:5672/test?sslmode=prefer"
	assert.Equal(t, expectedUrl, config.DBConnStr())
}

func TestLoadConfigurationNonExistingFile(t *testing.T) {
	_, err := LoadConfiguration("non_existing_file.env")
	assert.NotNil(t, err, "Expected error when loading non-existing file")
}
