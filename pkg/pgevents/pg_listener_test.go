package pgevents

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxtest"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

var defaultConnTestRunner pgxtest.ConnTestRunner

func init() {
	defaultConnTestRunner = pgxtest.DefaultConnTestRunner()
	defaultConnTestRunner.CreateConfig = func(ctx context.Context, t testing.TB) *pgx.ConnConfig {
		configuration, err := config.LoadConfiguration("../../.env")
		if err != nil {
			t.Errorf("Failed to create db pool: %s", err.Error())
		}
		conf, err := pgx.ParseConfig(configuration.DBConnStr())

		configuration.LogLevel = "mute" // suppress log output
		log.Setup(configuration)

		if err != nil {
			t.Errorf("Failed to parse config: %s", err.Error())
		}

		return conf
	}
}

func TestPGListenerStartListening(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	defaultConnTestRunner.RunTest(ctx, t, func(ctx context.Context, t testing.TB, conn *pgx.Conn) {

		listener := &PGListener{
			Connect: func(ctx context.Context) (*pgx.Conn, error) {
				config := defaultConnTestRunner.CreateConfig(ctx, t)
				return pgx.ConnectConfig(ctx, config)
			},
		}

		notificationCh := make(chan *Notification)

		listener.RegisterHandler("channel", HandlerFunc(func(notification *Notification) error {
			select {
			case notificationCh <- notification:
			}
			return nil
		}))

		listenerCtx, listenerCtxCancel := context.WithCancel(ctx)
		defer listenerCtxCancel()
		listenerDoneChan := make(chan struct{})

		go func() {
			listener.StartListening(listenerCtx)
			close(listenerDoneChan)
		}()

		// Wait for the listener to start
		time.Sleep(2 * time.Second)

		notificationData := &Notification{
			ID:      "1",
			Type:    "type",
			Payload: "payload",
		}

		notificationBytes, err := json.Marshal(notificationData)
		require.NoError(t, err)

		msg := string(notificationBytes)
		halfLength := len(msg) / 2

		firstHalf, secondHalf := msg[:halfLength], msg[halfLength:]

		_, err = conn.Exec(ctx, "select pg_notify($1, $2)", "channel", "1:2:"+firstHalf)
		require.NoError(t, err)

		_, err = conn.Exec(ctx, "select pg_notify($1, $2)", "channel", "2:2:"+secondHalf)
		require.NoError(t, err)

		select {
		case notification := <-notificationCh:
			require.Equal(t, notificationData, notification)
		case <-ctx.Done():
			t.Fatalf("error %v", ctx.Err())
		}

		listener.Close(ctx)
		listenerCtxCancel()

		// Wait for Listen to finish.
		select {
		case <-listenerDoneChan:

		case <-ctx.Done():
			t.Fatalf("ctx cancelled while waiting for Listen() to return: %v", ctx.Err())
		}
	})
}

func TestPGListenerStartListeningInvalidMessage(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	defaultConnTestRunner.RunTest(ctx, t, func(ctx context.Context, t testing.TB, conn *pgx.Conn) {

		listener := &PGListener{
			Connect: func(ctx context.Context) (*pgx.Conn, error) {
				config := defaultConnTestRunner.CreateConfig(ctx, t)
				return pgx.ConnectConfig(ctx, config)
			},
		}

		notificationCh := make(chan *Notification)

		listener.RegisterHandler("channel", HandlerFunc(func(notification *Notification) error {
			select {
			case notificationCh <- notification:
			}
			return nil
		}))

		listenerCtx, listenerCtxCancel := context.WithCancel(ctx)
		defer listenerCtxCancel()
		listenerDoneChan := make(chan struct{})

		go func() {
			listener.StartListening(listenerCtx)
			close(listenerDoneChan)
		}()

		// Wait for the listener to start
		time.Sleep(2 * time.Second)

		_, err := conn.Exec(ctx, "select pg_notify($1, $2)", "channel", ":1:1:invalid-message")
		require.NoError(t, err)

		_, err = conn.Exec(ctx, "select pg_notify($1, $2)", "channel", "0::invalid-message")
		require.NoError(t, err)

		listener.Close(ctx)
		listenerCtxCancel()

		// Wait for Listen to finish.
		select {
		case <-listenerDoneChan:

		case <-ctx.Done():
			t.Fatalf("ctx cancelled while waiting for Listen() to return: %v", ctx.Err())
		}
	})
}

func TestPGListenerStartListeningInvalidJSON(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	defaultConnTestRunner.RunTest(ctx, t, func(ctx context.Context, t testing.TB, conn *pgx.Conn) {

		listener := &PGListener{
			Connect: func(ctx context.Context) (*pgx.Conn, error) {
				config := defaultConnTestRunner.CreateConfig(ctx, t)
				return pgx.ConnectConfig(ctx, config)
			},
		}

		notificationCh := make(chan *Notification)

		listener.RegisterHandler("channel", HandlerFunc(func(notification *Notification) error {
			select {
			case notificationCh <- notification:
			}
			return nil
		}))

		listenerCtx, listenerCtxCancel := context.WithCancel(ctx)
		defer listenerCtxCancel()
		listenerDoneChan := make(chan struct{})

		go func() {
			listener.StartListening(listenerCtx)

			close(listenerDoneChan)
		}()

		// Wait for the listener to start
		time.Sleep(2 * time.Second)

		_, err := conn.Exec(ctx, "select pg_notify($1, $2)", "channel", "1:1:invalid-message")
		require.NoError(t, err)

		listener.Close(ctx)
		listenerCtxCancel()

		// Wait for Listen to finish.
		select {
		case <-listenerDoneChan:

		case <-ctx.Done():
			t.Fatalf("ctx cancelled while waiting for Listen() to return: %v", ctx.Err())
		}
	})
}

func TestPGListenerStartListeningHandlerError(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	defaultConnTestRunner.RunTest(ctx, t, func(ctx context.Context, t testing.TB, conn *pgx.Conn) {

		listener := &PGListener{
			Connect: func(ctx context.Context) (*pgx.Conn, error) {
				config := defaultConnTestRunner.CreateConfig(ctx, t)
				return pgx.ConnectConfig(ctx, config)
			},
		}

		expError := fmt.Errorf("error")

		listener.RegisterHandler("channel", HandlerFunc(func(notification *Notification) error {

			return expError
		}))

		listenerCtx, listenerCtxCancel := context.WithCancel(ctx)
		defer listenerCtxCancel()
		listenerDoneChan := make(chan struct{})

		go func() {
			listener.StartListening(listenerCtx)

			close(listenerDoneChan)
		}()

		// Wait for the listener to start
		time.Sleep(2 * time.Second)
		notificationData := &Notification{
			ID:      "1",
			Type:    "type",
			Payload: "payload",
		}

		notificationBytes, err := json.Marshal(notificationData)
		require.NoError(t, err)

		msg := string(notificationBytes)

		_, err = conn.Exec(ctx, "select pg_notify($1, $2)", "channel", "1:1:"+msg)
		require.NoError(t, err)

		_, err = conn.Exec(ctx, "select pg_notify($1, $2)", "invalid_test", "1:1:"+msg)
		require.NoError(t, err)

		listener.Close(ctx)
		listenerCtxCancel()

		// Wait for Listen to finish.
		select {
		case <-listenerDoneChan:

		case <-ctx.Done():
			t.Fatalf("ctx cancelled while waiting for Listen() to return: %v", ctx.Err())
		}
	})
}

func TestPGListenerStartListening_(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	defaultConnTestRunner.RunTest(ctx, t, func(ctx context.Context, t testing.TB, conn *pgx.Conn) {

		listener := &PGListener{
			Connect: func(ctx context.Context) (*pgx.Conn, error) {
				config := defaultConnTestRunner.CreateConfig(ctx, t)
				return pgx.ConnectConfig(ctx, config)
			},
		}

		listener.RegisterHandler(" 1 select channel", HandlerFunc(func(notification *Notification) error {

			return nil
		}))

		listenerCtx, listenerCtxCancel := context.WithCancel(ctx)
		defer listenerCtxCancel()
		listenerDoneChan := make(chan struct{})

		go func() {
			listener.StartListening(listenerCtx)

			close(listenerDoneChan)
		}()

		listener.Close(ctx)
		listenerCtxCancel()

		// Wait for Listen to finish.
		select {
		case <-listenerDoneChan:

		case <-ctx.Done():
			t.Fatalf("ctx cancelled while waiting for Listen() to return: %v", ctx.Err())
		}
	})
}

func TestPGListenerStartListening_InvalidChannelName(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	defaultConnTestRunner.RunTest(ctx, t, func(ctx context.Context, t testing.TB, conn *pgx.Conn) {

		listener := &PGListener{
			Connect: func(ctx context.Context) (*pgx.Conn, error) {
				config := defaultConnTestRunner.CreateConfig(ctx, t)
				return pgx.ConnectConfig(ctx, config)
			},
		}

		listener.RegisterHandler("*", HandlerFunc(func(notification *Notification) error {

			return nil
		}))

		listenerCtx, listenerCtxCancel := context.WithCancel(ctx)
		defer listenerCtxCancel()
		listenerDoneChan := make(chan struct{})

		go func() {
			listener.StartListening(listenerCtx)

			close(listenerDoneChan)
		}()

		listener.Close(ctx)
		listenerCtxCancel()

		// Wait for Listen to finish.
		select {
		case <-listenerDoneChan:

		case <-ctx.Done():
			t.Fatalf("ctx cancelled while waiting for Listen() to return: %v", ctx.Err())
		}
	})
}

func TestPGListenerStartListening_NoConnectFunc(t *testing.T) {
	listener := &PGListener{}

	listenerCtx, listenerCtxCancel := context.WithCancel(context.Background())
	defer listenerCtxCancel()

	err := listener.StartListening(listenerCtx)
	if err == nil {
		t.Fatalf("expecting to receive an error")
	}
}

func TestPGListenerStartListening_NoHandler(t *testing.T) {
	listener := &PGListener{
		Connect: func(ctx context.Context) (*pgx.Conn, error) {
			return nil, nil
		},
	}

	listenerCtx, listenerCtxCancel := context.WithCancel(context.Background())
	defer listenerCtxCancel()

	err := listener.StartListening(listenerCtx)
	if err == nil {
		t.Fatalf("expecting to receive an error")
	}
}

func TestPGListenerStartListening_Constructor(t *testing.T) {
	configuration, err := config.LoadConfiguration("../../.env")
	if err != nil {
		t.Errorf("Failed to create db pool: %s", err.Error())
	}
	listener, _ := New(configuration.DBConnStr())

	listenerCtx, listenerCtxCancel := context.WithDeadline(context.Background(), time.Now().Add(time.Second))
	defer listenerCtxCancel()

	listener.RegisterHandler("test", HandlerFunc(func(notification *Notification) error {
		listenerCtxCancel()
		return nil
	}))

	err = listener.StartListening(listenerCtx)
	if err == nil {
		t.Fatalf("expecting to receive an error")
	}

}
