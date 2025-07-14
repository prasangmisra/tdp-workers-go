package pgevents

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgconn"

	"github.com/jackc/pgx/v5"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

type Listener interface {
	Close(ctx context.Context)
	RegisterHandler(channel string, handler Handler)
	StartListening(ctx context.Context) error
}

type PGListener struct {
	Connect  func(ctx context.Context) (*pgx.Conn, error)
	handlers map[string]Handler
}

func (l *PGListener) RegisterHandler(channel string, handler Handler) {
	if l.handlers == nil {
		l.handlers = make(map[string]Handler)
	}

	l.handlers[channel] = handler
}

func (l *PGListener) StartListening(ctx context.Context) error {
	if l.Connect == nil {
		return fmt.Errorf("listen: Connect is nil")
	}

	if l.handlers == nil {
		return fmt.Errorf("listen: No handlers")
	}

	// if connecting to the database fails it will wait a while and try to reconnect.
	for {
		err := l._connect(ctx)
		if err != nil {
			log.Error(types.LogMessages.DatabaseConnectionFailed, log.Fields{
				types.LogFieldKeys.Error: err.Error(),
			})
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			time.Sleep(time.Minute)
		}
	}
}

func (l *PGListener) _connect(ctx context.Context) error {
	conn, err := l.Connect(ctx)
	if err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	defer conn.Close(ctx)

	for channel := range l.handlers {
		_, err := conn.Exec(ctx, "listen "+pgx.Identifier{channel}.Sanitize())
		if err != nil {
			return fmt.Errorf("listen %q: %w", channel, err)
		}
	}

	err = l.listen(ctx, conn)
	if err != nil {
		return err
	}

	<-ctx.Done()
	return ctx.Err()
}

func (l *PGListener) listen(ctx context.Context, conn *pgx.Conn) error {

	data := notificationData{}

	for {
		notification, err := conn.WaitForNotification(ctx)
		if err != nil {
			return fmt.Errorf("waiting for notification: %w", err)
		}

		payload := notification.Payload
		parts := strings.SplitN(payload, ":", 3)
		data.receivedParts, err = strconv.Atoi(parts[0])
		if err != nil {
			log.Error("invalid 'part' received")
			data.reset()
			continue
		}

		data.totalParts, err = strconv.Atoi(parts[1])
		if err != nil {
			log.Error("invalid 'total_parts' received")
			data.reset()
			continue
		}

		if data.receivedParts <= data.totalParts {
			data.fullPayload += parts[2]

			if data.receivedParts < data.totalParts {
				continue
			}
		}

		log.Debug("Payload:", log.Fields{"payload": data.fullPayload})
		notification.Payload = data.fullPayload

		data.reset()

		err = l.handleNotification(notification)
		if err != nil {
			log.Error("error handling notification", log.Fields{
				"channel":                notification.Channel,
				types.LogFieldKeys.Error: err.Error(),
			})
		}

	}

}
func (l *PGListener) handleNotification(notification *pgconn.Notification) error {
	meta := new(Notification)

	err := json.Unmarshal([]byte(notification.Payload), &meta)
	if err != nil {
		return fmt.Errorf("json.Unmarshal %v error: %w", notification.Payload, err)
	}

	if handler, ok := l.handlers[notification.Channel]; ok {
		err := handler.HandleNotification(meta)
		if err != nil {
			return fmt.Errorf("handle %s notification: %w", notification.Channel, err)
		}
	} else {
		return fmt.Errorf("missing handler: %s", notification.Channel)
	}

	return nil
}

func (l *PGListener) Close(ctx context.Context) {
	conn, err := l.Connect(ctx)
	if err != nil {
		return
	}
	_, err = conn.Exec(ctx, "UNLISTEN *")
	if err != nil {
		return
	}
	err = conn.Close(ctx)
	if err != nil {
		return
	}
}
