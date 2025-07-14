//go:build integration

package service

import (
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-notifications/subscription-manager-service/internal/app/config"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
	"testing"
)

type TestSuite struct {
	suite.Suite
	db   database.Database
	srvc *Service
	cfg  *config.Config
}

func TestSubscriptionSuite(t *testing.T) {
	suite.Run(t, new(TestSuite))
}

func (suite *TestSuite) SetupSuite() {
	cfg, err := config.LoadConfiguration("../../../configs")
	suite.NoError(err)
	suite.cfg = &cfg
	suite.srvc = createService(suite.T(), suite.cfg)
}

func createService(t *testing.T, cfg *config.Config) *Service {
	t.Helper()

	domainsDB, err := database.New(cfg.DomainsDB.PostgresPoolConfig(), &logger.MockLogger{})
	require.NoError(t, err, "Failed to create Domains DB connection")
	subDB, err := database.New(cfg.SubscriptionDB.PostgresPoolConfig(), &logger.MockLogger{})
	require.NoError(t, err, "Failed to create Subscription DB connection")
	service, err := New(domainsDB, subDB, cfg)
	require.NoError(t, err, "Failed to create service")

	t.Log("successfully created service")
	return service
}
