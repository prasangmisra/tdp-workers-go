package handler

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/enqueuer"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

const (
	accreditationName = "test-accreditation"
)

func TestEnqueuerTestSuite(t *testing.T) {
	suite.Run(t, new(EnqueuerTestSuite))
}

type EnqueuerTestSuite struct {
	suite.Suite
	db       database.Database
	mb       *mocks.MockMessageBus
	enqueuer enqueuer.DbMessageEnqueuer[*model.PollMessage]

	service *WorkerService
}

func (s *EnqueuerTestSuite) SetupSuite() {
	config, err := config.LoadConfiguration("../../.env")
	s.NoError(err, "Failed to read config from .env")

	config.LogLevel = "mute" // suppress log output
	log.Setup(config)

	db, err := database.New(config.PostgresPoolConfig(), config.GetDBLogLevel())
	s.NoError(err, types.LogMessages.DatabaseConnectionFailed)
	s.db = db
}

func (s *EnqueuerTestSuite) SetupTest() {
	s.mb = &mocks.MockMessageBus{}
	pendingStatusID := s.db.GetPollMessageStatusId("pending")
	submittedStatusID := s.db.GetPollMessageStatusId("submitted")
	enqueuerConfig, err := enqueuer.NewDbEnqueuerConfigBuilder[*model.PollMessage]().
		WithQueryExpression("status_id = ? OR (status_id = ? AND last_submitted_date <= ?)").
		WithQueryValues([]any{
			pendingStatusID,
			submittedStatusID,
			time.Now().Add(-10 * time.Minute),
		}).
		WithUpdateFieldValueMap(map[string]interface{}{
			"last_submitted_date": time.Now(),
			"status_id":           submittedStatusID},
		).
		WithQueue("WorkerPollMessages").
		Build()
	s.NoError(err, "Failed to config enqueuer")

	enq := enqueuer.DbMessageEnqueuer[*model.PollMessage]{
		Db:     s.db.GetDB(),
		Bus:    s.mb,
		Config: enqueuerConfig,
	}
	s.enqueuer = enq

	s.service = NewWorkerService(s.mb, s.db)
}

func insertTestPollMessage(db database.Database, id string) (err error) {
	tx := db.GetDB()

	data := ryinterface.DomainInfoResponse{
		Name: "example.com",
	}
	serializedData, _ := json.Marshal(&data)

	var typeId string
	sql := `SELECT tc_id_from_name('poll_message_type',?)`
	err = tx.Raw(sql, "domain_info").Scan(&typeId).Error
	if err != nil {
		return
	}

	sql = `INSERT INTO poll_message(id, accreditation, epp_message_id, type_id, data) VALUES(?, ?, ?, ?, ?)`
	err = tx.Exec(sql, id, accreditationName, uuid.NewString(), typeId, serializedData).Error

	return
}

func (s *EnqueuerTestSuite) TestHandler() {
	ctx := context.Background()

	messageId := uuid.NewString()
	err := insertTestPollMessage(s.db, messageId)
	s.NoError(err, "Failed to insert test poll message")

	s.mb.On("Send", ctx, "WorkerPollMessages", mock.Anything, mock.Anything).Return(nil)
	err = s.enqueuer.EnqueuerDbMessages(ctx, s.service.DBPollMessageHandler)
	s.NoError(err)
}
