package enqueuer

import (
	"context"
	"fmt"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
	"google.golang.org/protobuf/proto"
	"gorm.io/gorm"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
)

type DbMessageEnqueuer[T DBModel] struct {
	Db     *gorm.DB
	Bus    messagebus.MessageBus
	Config *DbEnqueuerConfig[T]
}

// getRows query messages with the configured condition
func (e DbMessageEnqueuer[T]) getRows(ctx context.Context) (rows []T, err error) {
	whereCondition := e.Config.QueryExpression
	whereValues := e.Config.QueryValues
	limit := e.Config.BatchSize
	orderByExpression := e.Config.OrderByExpression

	query := e.Db.WithContext(ctx).Limit(limit).Where(whereCondition, whereValues...)
	if orderByExpression != "" {
		orderClause := fmt.Sprintf("%s %s", orderByExpression, e.Config.OrderByDirection.String())
		query = query.Order(orderClause)
	}

	err = query.Find(&rows).Error
	return
}

// updateRows query messages with the configured condition
func (e DbMessageEnqueuer[T]) updateRows(ctx context.Context, Ids []string) (err error) {
	err = e.Db.WithContext(ctx).
		Model(e.Config.UpdateModel).
		Where("ID IN ?", Ids).
		Updates(e.Config.UpdateFieldValueMap).
		Error
	return
}

func (e DbMessageEnqueuer[T]) processRows(ctx context.Context, rows []T, handler func(T) (proto.Message, error)) (err error) {
	var ids []string

	if e.Config.UpdateFieldValueMap != nil {
		defer func(ctx context.Context, Ids *[]string) {
			err = e.updateRows(ctx, *Ids)
			if err != nil {
				log.Error("Updating enqueuer rows failed", log.Fields{
					types.LogFieldKeys.Error: err.Error(),
				})
			}
		}(ctx, &ids)
	}

	for _, row := range rows {
		// convert row to proto
		protoMsg, err := handler(row)
		if err != nil {
			return err
		}

		// publish message
		err = e.publishRow(ctx, protoMsg)
		if err != nil {
			return err
		}

		// get message ID
		if e.Config.UpdateFieldValueMap != nil {
			id := row.GetID()
			ids = append(ids, id)
		}
	}
	return nil
}

// publishRow publish message to queue
func (e DbMessageEnqueuer[T]) publishRow(ctx context.Context, msg proto.Message) (err error) {
	err = e.Bus.Send(ctx, e.Config.Queue, msg, nil)
	return
}

// EnqueuerDbMessages read messages from db and publish them to message bus
func (e DbMessageEnqueuer[T]) EnqueuerDbMessages(ctx context.Context, handler func(T) (proto.Message, error)) (err error) {
	// validate config select conditions
	if e.Config == nil {
		return fmt.Errorf("configs must be provid")
	}

	for {
		select {
		case <-ctx.Done():
			// Context canceled, exit loop
			return ctx.Err()
		default:
			// Call function to get rows from DB
			rows, err := e.getRows(ctx)
			if err != nil {
				return err
			}

			if len(rows) == 0 {
				return nil
			}
			log.Debug("enqueuer started processing")

			// parse, publish, and update
			err = e.processRows(ctx, rows, handler)
			if err != nil {
				return err
			}
		}
	}
}
