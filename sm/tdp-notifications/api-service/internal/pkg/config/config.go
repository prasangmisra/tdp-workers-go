package config

import (
	"fmt"
	"github.com/go-playground/validator/v10"
	"github.com/spf13/viper"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
	"strings"
)

const (
	RABBITMQ_HOSTNAME_KEY        = "RABBITMQ_HOSTNAME"
	RABBITMQ_PORT_KEY            = "RABBITMQ_PORT"
	RABBITMQ_TLS_ENABLED_KEY     = "RABBITMQ_TLS_ENABLED"
	RABBITMQ_TLS_SKIP_VERIFY_KEY = "RABBITMQ_TLS_SKIP_VERIFY"
	LOG_OUTPUT_SINK_KEY          = "LOG_OUTPUT_SINK"
	AMQPS                        = "amqps"
	AMQP                         = "amqp"
)

type RMQ struct {
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
}

type HealthCheck struct {
	Frequency int `yaml:"frequency"`
	Latency   int `yaml:"latency"`
	Timeout   int `yaml:"timeout"`
}

type Validator struct {
	HttpsUrl        bool `yaml:"httpsurl"`
	UrlReachability bool `yaml:"urlreachability"`
}

type Config struct {
	Log         zap.LoggerConfig `yaml:"log"`
	ServicePort string           `yaml:"servicePort" validate:"required"`
	SwaggerURL  string           `yaml:"swaggerURL"`
	HealthCheck `yaml:"healthCheck"`
	RMQ         `yaml:"rmq"`
	Validator
}

func LoadConfiguration(configPath string) (config Config, err error) {
	env := GetEnvironment()

	// Set Logging Environment
	config.Log.Environment = env.LoggingEnv()
	config.Log.OutputSink = "stderr"

	viper.SetDefault("Validator.HttpsUrl", true)
	viper.SetDefault("Validator.UrlReachability", true)

	viper.SetConfigName(env.String())
	viper.SetConfigType("yaml")
	viper.AddConfigPath(configPath)

	viper.SetEnvPrefix(env.String())
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

	if err := viper.ReadInConfig(); err != nil {
		return config, fmt.Errorf("cannot read configuration file: %w", err)
	}

	if err := viper.Unmarshal(&config); err != nil {
		return config, fmt.Errorf("unable to decode configuration: %w", err)
	}

	config.Log.RedactValues = append(config.Log.RedactValues, config.RMQ.Password)

	if err := validator.New().Struct(config); err != nil {
		return config, fmt.Errorf("error validating configuration: %w", err)
	}

	return config, nil
}

// RMQurl returns the RabbitMQ URL based on the configuration.
func (c Config) RMQurl() string {
	return fmt.Sprintf(
		"%v://%v:%v@%v:%v",
		c.RMQprotocol(),
		c.RMQ.Username,
		c.RMQ.Password,
		c.RMQ.HostName,
		c.RMQ.Port,
	)
}

func (c Config) RMQprotocol() string {
	if c.RMQ.TLSEnabled {
		return AMQPS
	}
	return AMQP
}
