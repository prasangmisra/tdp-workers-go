package enqueuer

/*
This code was taken from the tdp-workers-go repo; it was mostly copied as is, with some minor modifications.
The original code can be found at:  https://github.com/tucowsinc/tdp-workers-go/tree/develop/pkg/enqueuer

The only changes made to this class is the addition of few comments, and support for SQL "Raw SELECT" statements.
*/

import (
	"context"
	"fmt"

	"github.com/tucowsinc/tdp-notifications/enqueuer/internal/types"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"google.golang.org/protobuf/proto"
	"gorm.io/gorm"

	"maps"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
)

type DbMessageEnqueuer[T DBModel] struct {
	Db     *gorm.DB
	Bus    messagebus.MessageBus
	Config *DbEnqueuerConfig[T]
	Log    logger.ILogger
}

// getRows query messages with the configured condition
func (e DbMessageEnqueuer[T]) getRows(ctx context.Context) (rows []T, err error) {
	whereCondition := e.Config.QueryExpression
	whereValues := e.Config.QueryValues
	limit := e.Config.BatchSize
	orderByExpression := e.Config.OrderByExpression

	if e.Config.RawSelect == "" {
		query := e.Db.WithContext(ctx).Limit(limit).Where(whereCondition, whereValues...)
		if orderByExpression != "" {
			orderClause := fmt.Sprintf("%s %s", orderByExpression, e.Config.OrderByDirection.String())
			query = query.Order(orderClause)
		}
		err = query.Find(&rows).Error
	} else {
		err = e.Db.WithContext(ctx).Raw(e.Config.RawSelect, whereValues...).Scan(&rows).Error
	}
	return
}

// updateRows query messages with the configured condition
func (e DbMessageEnqueuer[T]) updateRows(ctx context.Context, Ids []string) (err error) {
	return e.Db.WithContext(ctx).
		Model(new(T)).
		Where("ID IN ?", Ids).
		Updates(e.Config.UpdateFieldValueMap).
		Error
}

// processRows converts each row to a proto.Message and publishes it.
func (e DbMessageEnqueuer[T]) processRows(ctx context.Context, rows []T, handler func(T) (proto.Message, error)) (err error) {
	var ids []string

	if e.Config.UpdateFieldValueMap != nil {
		defer func(ctx context.Context, Ids *[]string) {
			// If the main code errored out, this deferred function will still execute, so we have to check if the error is nil; we only want to run the updateRows if there was no error
			if err == nil {
				err2 := e.updateRows(ctx, *Ids)
				if err2 != nil {
					e.Log.Error("Updating enqueuer rows failed", logger.Fields{
						types.LogFieldKeys.Error: err2.Error(),
					})
				}
			}
		}(ctx, &ids)
	}

	for _, row := range rows {
		msg, err := handler(row)
		if err != nil {
			return fmt.Errorf("failed to convert row to proto message: %w", err)
		}

		err = e.publishRow(ctx, row, msg)
		if err != nil {
			return fmt.Errorf("failed to publish message: %w", err)
		}

		if e.Config.UpdateFieldValueMap != nil {
			ids = append(ids, row.GetID())
		}
	}
	return nil
}

// publishRow sends the proto message to the configured queue with headers.
func (e DbMessageEnqueuer[T]) publishRow(ctx context.Context, row T, msg proto.Message) error {
	e.Log.Info("Publishing message to queue...", logger.Fields{
		"queue": e.Config.Queue,
	})

	headers := make(map[string]any)
	maps.Copy(headers, e.Config.Headers)
	headers["correlation_id"] = row.GetID()
	err := e.Bus.Send(ctx, e.Config.Queue, msg, headers)
	return err
}

// EnqueuerDbMessages kicks off the fetch-transform-publish loop for messages.
func (e DbMessageEnqueuer[T]) EnqueuerDbMessages(ctx context.Context, handler func(T) (proto.Message, error)) error {
	if e.Config == nil {
		return fmt.Errorf("enqueuer config must be provided")
	}

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			rows, err := e.getRows(ctx)
			if err != nil {
				return err
			}
			if len(rows) == 0 {
				return nil
			}

			e.Log.Debug("enqueuer started processing")
			if err := e.processRows(ctx, rows, handler); err != nil {
				return err
			}
		}
	}
}
