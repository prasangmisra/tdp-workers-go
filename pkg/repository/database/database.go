package database

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

var (
	ErrNotFound = gorm.ErrRecordNotFound
)

// Database represents the database layer
type Database interface {
	Ping(ctx context.Context) error

	// Transaction
	GetDB() *gorm.DB

	Begin() Database
	Commit() error
	Rollback() error
	WithTransaction(f func(Database) error) (err error)
	Close()
}

// database struct handles the communication with the postgres database
type database struct {
	pool *pgxpool.Pool
	gorm *gorm.DB
}

// New creates an instance of database and loads enum tables mapping
func New(config *pgxpool.Config, logLevel logger.LogLevel) (db *database, err error) {
	// create pgx pool instance
	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		log.Fatal(types.LogMessages.DatabaseConnectionFailed, log.Fields{
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	logger := logger.New(
		log.GetLogger(),
		logger.Config{
			LogLevel:                  logLevel,
			IgnoreRecordNotFoundError: true, // Ignore ErrRecordNotFound error for logger
		},
	)

	// create gorm instance
	gormDb, err := gorm.Open(
		postgres.New(
			postgres.Config{
				Conn: stdlib.OpenDBFromPool(pool),
			},
		),
		&gorm.Config{
			Logger:         logger,
			TranslateError: true,
		},
	)
	if err != nil {
		return
	}

	db = &database{
		pool: pool,
		gorm: gormDb,
	}

	return
}

// check if the methods expected by the domain.DB are implemented correctly
var _ Database = (*database)(nil)

// Ping checks the connection to the database.
func (db *database) Ping(ctx context.Context) error {
	return db.pool.Ping(ctx)
}

// GetDB returns gorm object or transaction
func (db *database) GetDB() *gorm.DB {
	return db.gorm
}

// Begin returns new instance of database with transaction
func (db *database) Begin() Database {
	return &database{
		gorm: db.gorm.Begin(),
	}
}

// Commit commits all changes made in transaction
func (db *database) Commit() error {
	return db.gorm.Commit().Error
}

// Rollback rollbacks all changes made in transaction
func (db *database) Rollback() error {
	return db.gorm.Rollback().Error
}

// WithTransaction executes function in db transaction, committing on success. Otherwise rolling back.
func (db *database) WithTransaction(f func(Database) error) (err error) {
	tx := db.Begin()

	defer func() {
		if err != nil {
			e := tx.Rollback()
			if e != nil {
				log.Error("error rolling back transaction", log.Fields{
					types.LogFieldKeys.Error: e.Error(),
				})
			}

			return
		}

		err = tx.Commit()
		if err != nil {
			log.Error("error committing transaction", log.Fields{
				types.LogFieldKeys.Error: err.Error(),
			})
		}
	}()

	return f(tx)
}

// Close closes the database connection
func (db *database) Close() {
	db.pool.Close()
}
