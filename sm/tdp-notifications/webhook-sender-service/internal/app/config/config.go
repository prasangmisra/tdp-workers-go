package config

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/go-playground/validator/v10"
	"github.com/spf13/viper"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
)

type Config struct {
	Log  zap.LoggerConfig `yaml:"log"`
	RMQ  RMQ              `yaml:"rmq" validate:"required"`
	HTTP HTTP             `yaml:"http" validate:"required"`
}

type HTTP struct {
	Timeout time.Duration `yaml:"timeout" validate:"required"`
}

type PriorityQueue struct {
	Name        string `yaml:"name" validate:"required"`
	MaxPriority int    `yaml:"maxPriority" validate:"required,min=1,max=255"`
}

type Queue struct {
	Name string `yaml:"name" validate:"required"`
}

type RetryQueuesConfig struct {
	RetryIntervals []int `yaml:"retryIntervals" validate:"min=1,dive,min=1"`
	MaxPriority    int   `yaml:"maxPriority" validate:"required,min=1,max=255"`
}

type RMQ struct {
	HostName                      string            `yaml:"hostName" validate:"required"`
	Port                          int               `yaml:"port" validate:"required"`
	Username                      string            `yaml:"username" validate:"required"`
	Password                      string            `yaml:"password" validate:"required"`
	Exchange                      string            `yaml:"exchange" validate:"required"`
	ExchangeKind                  string            `yaml:"exchangekind" validate:"required"`
	ExchangeDurable               bool              `yaml:"exchangeDurable" validate:"required"`
	QueueType                     string            `yaml:"queueType" validate:"required"`
	NotificationwebhookDLExchange string            `yaml:"notificationwebhookDLExchange" validate:"required"`
	WebhookSendQueue              PriorityQueue     `yaml:"webhookSendQueue" validate:"required"`
	FinalStatusQueue              Queue             `yaml:"finalStatusQueue" validate:"required"`
	RetryQueuesConfig             RetryQueuesConfig `yaml:"retryQueuesConfig" validate:"required"`
	RetryQueues                   []RetryQueue      `yaml:"-"`
	TLSEnabled                    bool              `yaml:"tlsenabled"`
	TLSSkipVerify                 bool              `yaml:"tlsskipverify"`
	VerifyServerName              string            `yaml:"verifyServerName"`
	Readers                       int               `yaml:"readers"`
	CertFile                      string            `yaml:"certFile"`
	KeyFile                       string            `yaml:"keyFile"`
	CAFile                        string            `yaml:"caFile"`
}

type RetryQueue struct {
	Name string
	TTL  int
}

func LoadConfiguration(configPath string) (cfg Config, err error) {
	env := GetEnvironment()

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

	cfg.Log.RedactValues = append(cfg.Log.RedactValues, cfg.RMQ.Password)

	if err := validator.New().Struct(cfg); err != nil {
		return cfg, fmt.Errorf("error validating configuration: %w", err)
	}

	retryQueues := make([]RetryQueue, len(cfg.RMQ.RetryQueuesConfig.RetryIntervals))
	for i, ttl := range cfg.RMQ.RetryQueuesConfig.RetryIntervals {
		retryQueues[i] = RetryQueue{
			Name: fmt.Sprintf("%s_retry_%d", cfg.RMQ.WebhookSendQueue.Name, i+1), // Naming convention
			TTL:  ttl,
		}
	}

	// Sort retry queues by TTL in ascending order
	sort.Slice(retryQueues, func(i, j int) bool {
		return retryQueues[i].TTL < retryQueues[j].TTL
	})

	cfg.RMQ.RetryQueues = retryQueues
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
