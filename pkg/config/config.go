package config

import (
	"crypto/tls"
	"fmt"
	"reflect"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"gorm.io/gorm/logger"

	"github.com/spf13/viper"
)

type Config struct {
	LogLevel       string `mapstructure:"LOG_LEVEL"`
	LogEnvironment string `mapstructure:"LOG_ENVIRONMENT"`
	LogOutputSink  string `mapstructure:"LOG_OUTPUT_SINK"`

	TestMode string `mapstructure:"TESTING_MODE"`

	RmqHostName         string `mapstructure:"RABBITMQ_HOSTNAME"`
	RmqPort             int    `mapstructure:"RABBITMQ_PORT"`
	RmqUserName         string `mapstructure:"RABBITMQ_USERNAME"`
	RmqPassword         string `mapstructure:"RABBITMQ_PASSWORD" secret:"true"`
	RmqExchangeName     string `mapstructure:"RABBITMQ_EXCHANGE"`
	RmqQueueName        string `mapstructure:"RABBITMQ_QUEUE"`
	RmqQueueType        string `mapstructure:"RABBITMQ_QUEUE_TYPE"`
	RmqTLSEnabled       bool   `mapstructure:"RABBITMQ_TLS_ENABLED"`
	RmqTLSSkipVerify    bool   `mapstructure:"RABBITMQ_TLS_SKIP_VERIFY"`
	RmqCertFile         string `mapstructure:"RABBITMQ_CERT_FILE"`
	RmqKeyFile          string `mapstructure:"RABBITMQ_KEY_FILE"`
	RmqCAFile           string `mapstructure:"RABBITMQ_CA_FILE"`
	RmqVerifyServerName string `mapstructure:"RABBITMQ_VERIFY_SERVER_NAME"`
	RmqPrefetchCount    int    `mapstructure:"RABBITMQ_PREFETCH_COUNT"`

	ServiceName     string `mapstructure:"SERVICE_NAME"`
	TracingEndPoint string `mapstructure:"TRACING_ENDPOINT"`
	TracingEnabled  bool   `mapstructure:"TRACING_ENABLED"`
	TracingInsecure bool   `mapstructure:"TRACING_INSECURE"`

	ServiceType string `mapstructure:"SERVICE_TYPE"`
	CronType    string `mapstructure:"CRON_TYPE"`

	MbReadersCount int `mapstructure:"MESSAGEBUS_READERS_COUNT"`

	DatabaseURL string `mapstructure:"DATABASE_URL"`
	DBPort      int    `mapstructure:"DBPORT"`
	DBMaxConn   int    `mapstructure:"DBMAXCONN"`
	DBUser      string `mapstructure:"DBUSER"`
	DBPass      string `mapstructure:"DBPASS" secret:"true"`
	DBHost      string `mapstructure:"DBHOST"`
	DBName      string `mapstructure:"DBNAME"`
	DBSSLMode   string `mapstructure:"DBSSLMODE"`

	AWSHostingApiKey          string `mapstructure:"AWS_HOSTING_API_KEY" secret:"true"`
	AWSHostingApiBaseEndpoint string `mapstructure:"AWS_HOSTING_API_BASE_ENDPOINT"`
	AWSSSOProfileName         string `mapstructure:"AWS_SSO_PROFILE_NAME"`
	AWSSqsQueueName           string `mapstructure:"AWS_SQS_QUEUE_NAME"`
	AWSSqsQueueAccountId      string `mapstructure:"AWS_SQS_QUEUE_ACCOUNT_ID"`
	AWSAccessKeyId            string `mapstructure:"AWS_ACCESS_KEY_ID" secret:"true"`
	AWSSecretAccessKey        string `mapstructure:"AWS_SECRET_ACCESS_KEY" secret:"true"`
	AWSSessionToken           string `mapstructure:"AWS_SESSION_TOKEN"`
	AWSRegion                 string `mapstructure:"AWS_REGION"`
	AWSRoles                  string `mapstructure:"AWS_ROLES"`

	NotificationQueueName string `mapstructure:"NOTIFICATION_QUEUE"`
	DNSCheckTimeout       int    `mapstructure:"DNS_CHECK_TIMEOUT"`
	DNSResolverAddress    string `mapstructure:"DNS_RESOLVER_ADDRESS"`
	DNSResolverPort       string `mapstructure:"DNS_RESOLVER_PORT"`
	DNSResolverRecursion  bool   `mapstructure:"DNS_RESOLVER_RECURSION"`
	HostingCNAMEDomain    string `mapstructure:"HOSTING_CNAME_DOMAIN"`

	CertBotApiBaseEndpoint string `mapstructure:"CERTBOT_API_BASE_ENDPOINT"`
	CertBotApiToken        string `mapstructure:"CERT_BOT_TOKEN" secret:"true"`
	CertBotApiTimeout      int    `mapstructure:"CERT_BOT_API_TIMEOUT"`

	APIRetryCount       int `mapstructure:"API_RETRY_COUNT"`
	APIRetryMinWaitTime int `mapstructure:"API_RETRY_MIN_WAIT_TIME"`
	APIRetryMaxWaitTime int `mapstructure:"API_RETRY_MAX_WAIT_TIME"`

	HealthcheckEnabled  bool `mapstructure:"HEALTHCHECK_ENABLED"`
	HealthcheckPort     int  `mapstructure:"HEALTHCHECK_PORT"`
	HealthcheckInterval int  `mapstructure:"HEALTHCHECK_INTERVAL"`
	HealthcheckTimeout  int  `mapstructure:"HEALTHCHECK_TIMEOUT"`
}

// IsDebugEnabled returns a boolean flag indicating if log debug level is enabled
func (c *Config) IsDebugEnabled() (isDebug bool) {
	switch strings.ToLower(c.LogLevel) {
	case "debug":
		isDebug = true
	default:
		isDebug = false
	}

	return
}

func LoadConfiguration(configFilePath string) (config Config, err error) {
	viper.SetConfigFile(configFilePath)
	viper.AutomaticEnv()

	err = viper.ReadInConfig()
	if err != nil {
		return
	}

	err = viper.Unmarshal(&config)

	return
}

func (c *Config) GetRedactValues() (redactedValues []string, err error) {
	v := reflect.Indirect(reflect.ValueOf(c))
	t := v.Type()

	for i := 0; i < t.NumField(); i++ {
		field := t.Field(i)
		secretTag := field.Tag.Get("secret")
		if secretTag == "true" {
			value := v.Field(i)

			switch value.Kind() {
			case reflect.String:
				value := strings.TrimSpace(value.String())
				if value != "" {
					redactedValues = append(redactedValues, value)
				}
			default:
				err = fmt.Errorf("unsupported field type: %v", value.Kind())
				return nil, err
			}
		}
	}

	return redactedValues, nil
}

func (c *Config) RmqUrl() string {
	return fmt.Sprintf(
		"%v://%v:%v@%v:%v",
		c.RmqProtocol(),
		c.RmqUserName,
		c.RmqPassword,
		c.RmqHostName,
		c.RmqPort,
	)
}

func (c *Config) RmqProtocol() string {
	if c.RmqTLSEnabled {
		return "amqps"
	}

	return "amqp"
}

func (c *Config) DBConnStr() string {
	if c.DatabaseURL != "" {
		return c.DatabaseURL
	}

	dbSslMode := c.DBSSLMode

	if dbSslMode == "" {
		dbSslMode = "prefer"
	}

	return fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=%s",
		c.DBUser, c.DBPass, c.DBHost, c.DBPort, c.DBName, dbSslMode,
	)
}

func (c *Config) PostgresPoolConfig() *pgxpool.Config {
	config, _ := pgxpool.ParseConfig(c.DBConnStr())
	config.ConnConfig.TLSConfig = &tls.Config{
		InsecureSkipVerify: true,
	}
	return config
}

func (c *Config) GetAPIRetryCount() int {
	if c.APIRetryCount == 0 {
		return 3
	}

	return c.APIRetryCount
}

func (c *Config) GetAPIMinWaitTime() time.Duration {
	if c.APIRetryMinWaitTime == 0 {
		return 5 * time.Second
	}

	return time.Duration(c.APIRetryMinWaitTime) * time.Second
}

func (c *Config) GetAPIMaxWaitTime() time.Duration {
	if c.APIRetryMaxWaitTime == 0 {
		return 15 * time.Second
	}

	return time.Duration(c.APIRetryMaxWaitTime) * time.Second
}

func (c *Config) GetCertBotApiTimeout() time.Duration {
	if c.CertBotApiTimeout == 0 {
		return 15 * time.Second
	}

	return time.Duration(c.CertBotApiTimeout) * time.Second
}

func (c *Config) GetDBLogLevel() logger.LogLevel {
	switch strings.ToLower(c.LogLevel) {
	case "debug":
		return logger.Info
	case "info", "warn", "error":
		return logger.Error
	default:
		return logger.Silent
	}
}
