package logging

import (
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/logger/zap"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

var log logger.ILogger

// Fields is a type alias for logger.Fields
type Fields = logger.Fields

// Setup initializes the logger with the provided configuration
func Setup(config config.Config) {
	redactValues, err := config.GetRedactValues()
	if err != nil {
		panic(err)
	}

	zapConfig := zap.LoggerConfig{
		Environment:  config.LogEnvironment, // specify the environment
		LogLevel:     config.LogLevel,       // specify the log level
		OutputSink:   config.LogOutputSink,
		Buffer:       nil,
		RedactValues: redactValues,
		CallerSkip:   types.ToPointer(3), // Since we are wrapping the logger, we need to skip the wrapper functions
	}

	log = zap.NewTdpLogger(zapConfig)
}

// GetLogger returns the logger instance
func GetLogger() logger.ILogger {
	if log == nil {
		panic("Logger not initialized")
	}
	return log
}

func Debug(message string, fields ...Fields) {

	log.Debug(message, fields...)
}

func Info(message string, fields ...Fields) {

	log.Info(message, fields...)
}

func Warn(message string, fields ...Fields) {

	log.Warn(message, fields...)
}

func Error(message string, fields ...Fields) {

	log.Error(message, fields...)
}

func Panic(message string, fields ...Fields) {

	log.Panic(message, fields...)
}

func Fatal(message string, fields ...Fields) {

	log.Fatal(message, fields...)
}

func Printf(message string, args ...interface{}) {

	log.Printf(message, args...)
}

func CreateChildLogger(fields ...logger.Fields) logger.ILogger {
	return log.CreateChildLogger(fields...)
}

func Sync() {
	log.Sync()
}
