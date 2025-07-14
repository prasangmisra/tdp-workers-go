package config

import "os"

type Environment string

const (
	Dev  Environment = "dev"
	Prod Environment = "prod"
)

var envLog = map[Environment]string{
	Dev:  "development",
	Prod: "production",
}

func (e Environment) LoggingEnv() string {
	return envLog[e]
}

// String is a method of Environment that returns the string representation of the environment.
func (e Environment) String() string {
	return string(e)
}

func GetEnvironment() Environment {
	if os.Getenv("ENV") == Prod.String() {
		return Prod
	}
	return Dev
}
