package commands

import (
	"fmt"
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
