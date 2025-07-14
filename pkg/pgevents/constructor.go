package pgevents

import (
	"context"
	"fmt"
	"github.com/jackc/pgx/v5"
)

func New(connString string) (Listener, error) {
	conf, err := pgx.ParseConfig(connString)
	if err != nil {
		return nil, fmt.Errorf("unable to convert conn string [%v] to pgx ParseConfig: %w", connString, err)
	}
	listener := &PGListener{
		Connect: func(ctx context.Context) (*pgx.Conn, error) {
			return pgx.ConnectConfig(ctx, conf)
		},
	}

	return listener, nil

}
