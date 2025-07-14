package mock

import (
	"context"

	"github.com/stretchr/testify/mock"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"google.golang.org/protobuf/proto"
)

// Mock implementation of MessageBus

// MockMessageBus is a mock for the MessageBus interface
// This helps us test interactions with the message bus without a real instance

type MockMessageBus struct {
	mock.Mock
}

func (m *MockMessageBus) Send(ctx context.Context, destination string, msg proto.Message, headers map[string]any) (msgId string, err error) {
	args := m.Called(ctx, destination, msg, headers)
	return args.String(0), args.Error(1)
}

func (m *MockMessageBus) Register(t proto.Message, f messagebus.HandlerFuncType) {}
func (m *MockMessageBus) Call(ctx context.Context, destination string, msg proto.Message, headers map[string]any) (string, messagebus.RpcResponse, error) {
	return "", messagebus.RpcResponse{}, nil
}
func (m *MockMessageBus) Consume(queue []string) error { return nil }
func (m *MockMessageBus) Ack(id string, isNack bool)   {}
func (m *MockMessageBus) WaitForResponses()            {}
func (m *MockMessageBus) Finalize()                    {}
func (m *MockMessageBus) DeclareQueue(name string, optFns ...messagebus.QueueOptionsFunc) error {
	return nil
}
