//go:build integration

package service

import (
	"fmt"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-shared-go/repository/v3/database"
	"testing"
)

const (
	username = "tucows"
	pass     = "tucows1234"
	host     = "domainsdb"
	port     = 5432
	dbname   = "tdpdb"
)

type TestSuite struct {
	suite.Suite
	db   database.Database
	srvc *service
}

func TestSubscriptionSuite(t *testing.T) {
	suite.Run(t, new(TestSuite))
}

func (suite *TestSuite) SetupSuite() {
	connStr := fmt.Sprintf("postgres://%v:%v@%v:%v/%v", username, pass, host, port, dbname)
	cfg, err := pgxpool.ParseConfig(connStr)
	suite.Require().NoError(err, "Failed to parse postgres config")
	suite.db, err = database.New(cfg, &logger.MockLogger{})
	suite.Require().NoError(err, "Failed to create Domains DB connection")
	suite.srvc = New(suite.db, &logger.MockLogger{})
}
