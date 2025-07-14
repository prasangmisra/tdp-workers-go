package config

import (
	"fmt"
	"strings"
	"time"

	"github.com/go-playground/validator/v10"
	"github.com/spf13/viper"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
)

type Config struct {
	Log        zap.LoggerConfig `yaml:"log"`
	RMQ        RMQ              `yaml:"rmq" validate:"required"`
	SMTPServer SMTPServer       `yaml:"smtpServer" validate:"required"`
}

type Queue struct {
	Name string `yaml:"name" validate:"required"`
}

type SMTPServer struct {
	Host          string        `yaml:"host" validate:"required"`
	Port          string        `yaml:"port" validate:"required"`
	Identity      string        `yaml:"identity"`
	Username      string        `yaml:"username" validate:"required"`
	Password      string        `yaml:"password" validate:"required"`
	RetryAttempts int           `yaml:"retryAttempts"`
	RetryMaxDelay time.Duration `yaml:"retryMaxDelay"`
}

type RMQ struct {
	HostName         string `yaml:"hostName" validate:"required"`
	Port             int    `yaml:"port" validate:"required"`
	Username         string `yaml:"username" validate:"required"`
	Password         string `yaml:"password" validate:"required"`
	Exchange         string `yaml:"exchange" validate:"required"`
	ExchangeKind     string `yaml:"exchangeKind" validate:"required"`
	ExchangeDurable  bool   `yaml:"exchangeDurable" validate:"required"`
	QueueType        string `yaml:"queueType"`
	EmailSendQueue   Queue  `yaml:"emailSendQueue" validate:"required"`
	FinalStatusQueue Queue  `yaml:"finalStatusQueue" validate:"required"`

	TLSEnabled       bool   `yaml:"tlsEnabled"`
	TLSSkipVerify    bool   `yaml:"tlsSkipVerify"`
	VerifyServerName string `yaml:"verifyServerName"`
	Readers          int    `yaml:"readers"`
	CertFile         string `yaml:"certFile"`
	KeyFile          string `yaml:"keyFile"`
	CAFile           string `yaml:"caFile"`
}

func LoadConfiguration(configPath string) (cfg Config, err error) {
	env := GetEnvironment()

	viper.SetDefault("smtpServer.retryAttempts", 3)
	viper.SetDefault("smtpServer.retryMaxDelay", time.Second)

	viper.SetConfigName(env.String())
	viper.SetConfigType("yaml")
	viper.AddConfigPath(configPath)

	viper.SetEnvPrefix(env.String())
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

	if err := viper.ReadInConfig(); err != nil {
		return cfg, fmt.Errorf("cannot read configuration file: %w", err)
	}

	if err := viper.Unmarshal(&cfg); err != nil {
		return cfg, fmt.Errorf("unable to decode configuration: %w", err)
	}

	cfg.Log.RedactValues = append(cfg.Log.RedactValues, cfg.RMQ.Password, cfg.SMTPServer.Password)

	if err := validator.New().Struct(cfg); err != nil {
		return cfg, fmt.Errorf("error validating configuration: %w", err)
	}

	return cfg, nil
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
		return "amqps"
	}
	return "amqp"
}
