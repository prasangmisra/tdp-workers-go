package config

import (
	"crypto/tls"
	"fmt"
	"strings"

	"github.com/go-playground/validator/v10"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/spf13/viper"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
)

type Database struct {
	HostName string `yaml:"hostname" validate:"required"`
	Port     int    `yaml:"port" validate:"required"`
	Username string `yaml:"username" validate:"required"`
	Password string `yaml:"password" validate:"required"`
	DBName   string `yaml:"dbname" validate:"required"`
}

type Config struct {
	Log zap.LoggerConfig `yaml:"log"`

	HealthCheck struct {
		Frequency int `yaml:"frequency"`
		Latency   int `yaml:"latency"`
		Timeout   int `yaml:"timeout"`
	} `yaml:"healthCheck"`

	RMQ RMQ `yaml:"rmq" validate:"required"`

	SubscriptionDB Database `yaml:"subscriptiondb" validate:"required"`
}

type RMQ struct {
	HostName               string `yaml:"hostname" validate:"required"`
	Port                   int    `yaml:"port" validate:"required"`
	Username               string `yaml:"username" validate:"required"`
	Password               string `yaml:"password" validate:"required"`
	Exchange               string `yaml:"exchange" validate:"required"`
	QueueType              string `yaml:"queueType"`
	FinalStatusQueue       Queue  `yaml:"finalstatusqueue" validate:"required"`
	EmailRenderingQueue    Queue  `yaml:"emailrenderingqueue" validate:"required"`
	EmailNotificationQueue Queue  `yaml:"emailnotificationqueue" validate:"required"`
	Readers                int    `yaml:"readers"`
	TLSEnabled             bool   `yaml:"tlsEnabled"`
	TLSSkipVerify          bool   `yaml:"tlsSkipVerify"`
	CertFile               string `yaml:"certFile"`
	KeyFile                string `yaml:"keyFile"`
	CAFile                 string `yaml:"caFile"`
	VerifyServerName       string `yaml:"verifyServerName"`
}

type Queue struct {
	Name string `yaml:"name" validate:"required"`
}

func LoadConfiguration(configPath string) (config Config, err error) {
	env := GetEnvironment()

	config.Log.Environment = env.LoggingEnv()
	config.Log.OutputSink = "stderr"

	viper.SetDefault("healthCheck.frequency", 30)
	viper.SetDefault("healthCheck.latency", 3)
	viper.SetDefault("healthCheck.timeout", 5)
	viper.SetDefault("rmq.queueName", "statusnotification")

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

	config.Log.RedactValues = append(config.Log.RedactValues, config.RMQ.Password, config.SubscriptionDB.Password)

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
		return "amqps"
	}

	return "amqp"
}

// DatabaseConnectionString returns the PostgreSQL database connection string based on the configuration.
func (c Database) DatabaseConnectionString() string {
	return fmt.Sprintf("postgres://%v:%v@%v:%v/%v", c.Username, c.Password, c.HostName, c.Port, c.DBName)
}

func (c Database) PostgresPoolConfig() *pgxpool.Config {
	config, _ := pgxpool.ParseConfig(c.DatabaseConnectionString())
	config.ConnConfig.TLSConfig = &tls.Config{
		InsecureSkipVerify: true,
	}
	return config
}
