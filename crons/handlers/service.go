package handlers

import (
	"context"
	"fmt"

	"github.com/tucowsinc/tdp-workers-go/pkg/enqueuer"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	message_bus "github.com/tucowsinc/tdp-workers-go/pkg/message_bus"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

type CronService struct {
	cfg config.Config
	db  database.Database
	bus messagebus.MessageBus
}

func NewCronService(cfg config.Config) (*CronService, error) {

	db, err := database.New(cfg.PostgresPoolConfig(), cfg.GetDBLogLevel())
	if err != nil {
		log.Fatal(types.LogMessages.DatabaseConnectionFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	mb, err := message_bus.SetupMessageBus(cfg)
	if err != nil {
		log.Fatal(types.LogMessages.MessageBusSetupFailed, log.Fields{
			types.LogFieldKeys.Error: err,
		})
	}

	return &CronService{
		cfg: cfg,
		db:  db,
		bus: mb,
	}, nil
}

// CronRouter routes the cron service to the appropriate handler based on the service type.
func (s *CronService) CronRouter(ctx context.Context) (err error) {

	switch s.cfg.CronType {
	case CronServiceTypeNameEnum.TransferInCron:
		err = s.ProcessPendingTransferInRequestMessage(ctx)
		if err != nil {
			return fmt.Errorf("error processing pending transfer in request message: %w", err)
		}
	case CronServiceTypeNameEnum.TransferAwayCron:
		err = s.ProcessTransferAwayOrders(ctx)
		if err != nil {
			return fmt.Errorf("error processing created transfer away orders: %w", err)
		}
	case CronServiceTypeNameEnum.DomainPurgeCron:
		err = s.ProcessDomainsPurge(ctx)
		if err != nil {
			return fmt.Errorf("error processing domain purge: %w", err)
		}
	case CronServiceTypeNameEnum.EventEnqueueCron:
		if s.cfg.NotificationQueueName == "" {
			log.Info("Notification queue name is not set, skipping event enqueue")
			return
		}
		var enq enqueuer.DbMessageEnqueuer[*model.VEventUnprocessed]
		enq, err = s.GetEventEnqueue()
		if err != nil {
			log.Error("Error configuring event enqueuer", log.Fields{
				types.LogFieldKeys.Error: err.Error(),
			})
			return
		}
		err = enq.EnqueuerDbMessages(context.Background(), EventEnqueueHandler)
		if err != nil {
			log.Fatal("Error starting enqueuer", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

	default:
		return fmt.Errorf("unknown service type: %s", s.cfg.CronType)
	}

	return nil
}

func (s *CronService) getDomainInfo(ctx context.Context, domainName string, acc *model.Accreditation) (*rymessages.DomainInfoResponse, error) {
	domainInfoMsg := &rymessages.DomainInfoRequest{Name: domainName}
	response, err := message_bus.Call(ctx, s.bus, types.GetTransformQueue(acc.Name), domainInfoMsg)
	if err != nil {
		return nil, err
	}

	domainInfoResp, ok := response.(*rymessages.DomainInfoResponse)
	if !ok {
		return nil, fmt.Errorf("unexpected message type received for domain info response: %T", response)
	}

	return domainInfoResp, nil
}

// Close closes the service.
func (s *CronService) Close() {
	s.db.Close()
	s.bus.Finalize()
}

func (s *CronService) GetEventEnqueue() (enq enqueuer.DbMessageEnqueuer[*model.VEventUnprocessed], err error) {
	enqueueConfig, err := enqueuer.NewDbEnqueuerConfigBuilder[*model.VEventUnprocessed]().
		WithUpdateFieldValueMap(map[string]interface{}{
			"is_processed": true,
		},
		).
		WithQueue(s.cfg.NotificationQueueName).
		WithOrderByExpression("created_at").
		WithBatchSize(DefaultUnProcessedEventBatchSize).
		WithUpdateModel(new(model.Event)).
		Build()
	if err != nil {
		log.Error("Error configuring enqueuer", log.Fields{"error": err})
		return
	}
	enq = enqueuer.DbMessageEnqueuer[*model.VEventUnprocessed]{
		Db:     s.db.GetDB(),
		Bus:    s.bus,
		Config: enqueueConfig,
	}
	return
}
