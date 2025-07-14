package main

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/sqs"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
	hostingproto "github.com/tucowsinc/tucows-domainshosting-app/cmd/functions/order/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func main() {
	cfg, err := config.LoadConfiguration(".env")

	log.Setup(cfg)
	defer log.Sync()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.LogID: uuid.NewString(),
	})

	if err != nil {
		logger.Fatal(types.LogMessages.ConfigurationLoadFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	logger.Info(types.LogMessages.ConfigurationLoaded)

	sqsPublisher, err := SetupSQSPublisher(context.Background(), cfg, logger)
	if err != nil {
		logger.Error("Failed to set up SQS publisher", log.Fields{
			types.LogFieldKeys.Error: err,
		})
		return
	}

	ids := []string{
		"58daa84e-ae1b-4296-90a9-2392eb215011",
		//	"36c50b12-d1e3-49fe-9931-c63b921d9319",
		//	"fdf69868-8fd1-4dd4-b219-a9c32adf8a87",
		//	"f6e1a378-d0d1-421d-8b34-657b13deba70",
		//	"4f3f44fc-f7d3-4ba0-831c-3689b15d323c",
		//	"80df7102-4b56-425b-91f3-14f4aebb8866",
	}

	for i := 1; i < 2; i++ {
		for _, id := range ids {
			jobLogger := logger.CreateChildLogger(log.Fields{
				types.LogFieldKeys.JobID:   id,
				types.LogFieldKeys.JobType: "OrderProcessing",
				types.LogFieldKeys.LogID:   uuid.NewString(),
			})
			productID := uuid.NewString()
			msg := &hostingproto.OrderDetailsResponse{
				Id:          id,
				ProductId:   productID,
				ProductName: "Static Website",
				ClientId:    uuid.NewString(),
				ClientName:  "test-client-name",
				DomainName:  "test-domain.com",
				Status:      fmt.Sprintf("Status %v", i),
				IsActive:    true,
				IsDeleted:   false,
				CreatedAt:   timestamppb.Now(),
			}

			_, err = sqsPublisher.Send(msg)
			if err != nil {
				jobLogger.Error("Error sending message to SQS", log.Fields{
					types.LogFieldKeys.ProductID: productID,
					types.LogFieldKeys.Error:     err,
				})
			} else {
				jobLogger.Info("Message successfully sent to SQS")
			}
		}
	}
}

func SetupSQSPublisher(ctx context.Context, cfg config.Config, logger logger.ILogger) (sqs.Publisher, error) {

	logger.Info("Initializing SQS publisher setup")

	ob := sqs.NewOptionsBuilder().
		WithDebugModeEnabled(cfg.IsDebugEnabled()).
		WithQueueName(cfg.AWSSqsQueueName).
		WithQueueAccountId(cfg.AWSSqsQueueAccountId).
		WithSSOProfileName(cfg.AWSSSOProfileName).
		WithAccessKeyId(cfg.AWSAccessKeyId).
		WithSecretAccessKey(cfg.AWSSecretAccessKey).
		WithSessionToken(cfg.AWSSessionToken).
		WithRegion(cfg.AWSRegion).
		WithRoles(cfg.AWSRoles)

	options, err := ob.Build()

	if err != nil {
		logger.Error("Error configuring SQS options", log.Fields{types.LogFieldKeys.Error: err})
		return nil, err
	}
	logger.Info("SQS options configured successfully")

	publisher, err := sqs.NewPublisher(ctx, *options)
	if err != nil {
		logger.Error("Error creating sqs publisher instance", log.Fields{types.LogFieldKeys.Error: err})
		return nil, err
	}

	logger.Info("SQL publisher successfully created")
	return publisher, nil
}
