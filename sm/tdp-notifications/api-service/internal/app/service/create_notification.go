package service

import (
	"context"

	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
)

func (s *Service) CreateNotification(ctx context.Context, test string, headers map[string]any, baseHeader *gcontext.BaseHeader) (string, error) {

	// Simulate some processing logic
	// In a real-world scenario, you would interact with the message bus here
	// and return the result or an error if something goes wrong
	// For this example, we'll just return a success message
	// along with the test string passed in
	return test, nil
}
