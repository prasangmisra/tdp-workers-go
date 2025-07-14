package mock

import (
	"sync"

	logger "github.com/tucowsinc/tdp-shared-go/logger"
)

var _ logger.ILogger = (*MockLogger)(nil)

type MockLogger struct {
	mu   sync.Mutex
	logs []string
}

// Store log messages
func (m *MockLogger) log(msg string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.logs = append(m.logs, msg)
}

// **Modify existing logging methods to capture logs**
func (m *MockLogger) Info(msg string, fields ...logger.Fields) {
	m.log(msg)
}

func (m *MockLogger) Debug(msg string, fields ...logger.Fields) {
	m.log(msg)
}

func (m *MockLogger) Error(msg string, fields ...logger.Fields) {
	m.log(msg)
}

func (m *MockLogger) Warn(msg string, fields ...logger.Fields) {
	m.log(msg)
}

func (m *MockLogger) Fatal(msg string, fields ...logger.Fields) {
	m.log(msg)
}

func (m *MockLogger) Panic(msg string, fields ...logger.Fields) {
	m.log(msg)
}

func (m *MockLogger) Printf(msg string, args ...interface{}) {
	m.log(msg)
}

func (m *MockLogger) Sync() error {
	return nil
}

func (m *MockLogger) CreateChildLogger(fields ...logger.Fields) logger.ILogger {
	return m
}

// **Add a method to retrieve logs**
func (m *MockLogger) GetLogs() []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.logs
}
