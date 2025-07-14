package handlers

import (
	"context"
	"fmt"
	"testing"

	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

type EventEnqueueCronTestSuite struct {
	suite.Suite
	service *CronService
	cfg     config.Config
	ctx     context.Context
}

func TestEventEnqueueCronTestSuite(t *testing.T) {
	suite.Run(t, new(EventEnqueueCronTestSuite))
}

func (suite *EventEnqueueCronTestSuite) SetupSuite() {
	suite.cfg = config.Config{
		NotificationQueueName: "test",
	}
	suite.service = &CronService{cfg: suite.cfg}
	suite.ctx = context.Background()
	log.Setup(suite.cfg)
}

func (suite *EventEnqueueCronTestSuite) TestEventEnqueueHandler() {
	eventID := "event1"
	parseError := fmt.Errorf("invalid character 'i' looking for beginning of value")

	tests := []struct {
		name          string
		event         model.VEventUnprocessed
		expectedError error
	}{
		{
			name: "test domain transfer event",
			event: model.VEventUnprocessed{
				ID:            eventID,
				EventTypeName: "domain_transfer",
				Payload:       []byte(`{"Name": "example.com"}`),
				TenantID:      "tenant1",
			},
			expectedError: nil,
		},
		{
			name: "UnsupportedEventType",
			event: model.VEventUnprocessed{
				ID:            eventID,
				EventTypeName: "unsupported_event",
				Payload:       []byte(`{}`),
				TenantID:      "tenant1",
			},
			expectedError: nil,
		},
		{
			name: "ErrorProcessingEvent",
			event: model.VEventUnprocessed{
				ID:            eventID,
				EventTypeName: "domain_transfer",
				Payload:       []byte(`invalid payload`),
				TenantID:      "tenant1",
			},
			expectedError: parseError,
		},
	}

	for _, tt := range tests {
		suite.Run(tt.name, func() {
			suite.SetupSuite()
			_, err := EventEnqueueHandler(&tt.event)
			if tt.expectedError != nil {
				suite.ErrorContains(err, tt.expectedError.Error())
			} else {
				suite.ErrorIs(err, nil)
			}
		})
	}
}
