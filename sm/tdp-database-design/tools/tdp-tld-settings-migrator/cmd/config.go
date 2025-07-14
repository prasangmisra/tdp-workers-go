package cmd

import (
	"crypto/tls"
	"fmt"
	"github.com/jackc/pgx/v5/pgxpool"
)

var dbConf dbConfig

type dbConfig struct {
	HostName string
	Port     int
	Username string
	Password string
	DBName   string
	Timeout  int
}

func (c *dbConfig) DatabaseConnectionString() string {
	return fmt.Sprintf("postgres://%v:%v@%v:%v/%v", c.Username, c.Password, c.HostName, c.Port, c.DBName)
}
func (c *dbConfig) PostgresPoolConfig() (*pgxpool.Config, error) {
	config, err := pgxpool.ParseConfig(c.DatabaseConnectionString())
	if err != nil {
		return nil, fmt.Errorf("unable to parse postgres config: %w", err)
	}
	config.ConnConfig.TLSConfig = &tls.Config{
		InsecureSkipVerify: true,
	}
	return config, nil
}
