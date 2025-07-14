package pgevents

import (
	"context"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/jackc/pgx/v5"
	"github.com/stretchr/testify/mock"
)

type MockListener struct {
	mock.Mock
	Listener
}

func (m *MockListener) Close(ctx context.Context) {
	m.Called(ctx)
}

func (m *MockListener) RegisterHandler(channel string, handler Handler) {
	m.Called(channel, handler)
}

func (m *MockListener) StartListening(ctx context.Context) error {
	args := m.Called(ctx)
	return args.Error(0)
}

func (m *MockListener) listen(ctx context.Context, conn *pgx.Conn) error {
	args := m.Called(ctx, conn)
	return args.Error(0)
}
func (m *MockListener) _connect(ctx context.Context) error {
	args := m.Called(ctx)
	return args.Error(0)
}

func (m *MockListener) handleNotification(notification *pgconn.Notification) error {
	args := m.Called(notification)
	return args.Error(0)
}
