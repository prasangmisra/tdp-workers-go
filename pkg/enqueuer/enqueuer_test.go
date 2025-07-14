package enqueuer

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/suite"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/mocks"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

const (
	accreditationName = "test-accreditation"
)

func insertTestPollMessage(db database.Database, id string) (err error) {
	tx := db.GetDB()

	data := ryinterface.DomainInfoResponse{
		Name: "example.com",
	}
	serializedData, err := json.Marshal(&data)

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

func TestEnqueuerTestSuite(t *testing.T) {
	suite.Run(t, new(EnqueuerTestSuite))
}

type EnqueuerTestSuite struct {
	suite.Suite
	db       database.Database
	mb       *mocks.MockMessageBus
	enqueuer DbMessageEnqueuer[*model.PollMessage]
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
	enqueuerConfig, err := NewDbEnqueuerConfigBuilder[*model.PollMessage]().
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
		//WithBatchSize(1234).
		Build()
	s.NoError(err, "Failed to config enqueuer")

	enqueuer := DbMessageEnqueuer[*model.PollMessage]{
		Db:     s.db.GetDB(),
		Bus:    s.mb,
		Config: enqueuerConfig,
	}
	s.enqueuer = enqueuer
}

func (s *EnqueuerTestSuite) TestGetRows() {
	ctx := context.Background()

	messageId := uuid.NewString()
	err := insertTestPollMessage(s.db, messageId)
	s.NoError(err, "Failed to insert test poll message")

	var rows []*model.PollMessage
	rows, err = s.enqueuer.getRows(ctx)
	s.NoError(err)
	s.NotNil(rows)
	s.Equal(messageId, rows[0].ID)
}

func (s *EnqueuerTestSuite) TestUpdateRows() {
	ctx := context.Background()

	messageId := uuid.NewString()
	err := insertTestPollMessage(s.db, messageId)
	s.NoError(err, "Failed to insert test poll message")

	var rows []*model.PollMessage
	rows, err = s.enqueuer.getRows(ctx)
	s.NotNil(rows)

	var ids []string
	for _, row := range rows {
		id := row.GetID()
		ids = append(ids, id)
	}
	err = s.enqueuer.updateRows(ctx, ids)
	s.NoError(err)
}
