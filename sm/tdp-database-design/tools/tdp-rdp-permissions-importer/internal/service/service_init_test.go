//go:build integration

package service

import (
	"context"
	"fmt"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/suite"
	"github.com/tucowsinc/tdp-shared-go/logger"
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
	db   *pgxpool.Pool
	srvc *service
}

func (suite *TestSuite) SetupSuite() {
	fmt.Println("Setting up test suite...")
	connStr := fmt.Sprintf("postgres://%v:%v@%v:%v/%v", username, pass, host, port, dbname)
	var err error
	suite.db, err = pgxpool.New(context.Background(), connStr)
	suite.Require().NoError(err, "Failed to create Domains DB connection")
	suite.srvc = New(suite.db, &logger.MockLogger{})
}

func TestPermissionSuite(t *testing.T) {
	suite.Run(t, new(TestSuite))
}
