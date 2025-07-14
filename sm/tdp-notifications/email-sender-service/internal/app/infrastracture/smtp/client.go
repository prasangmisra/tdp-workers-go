package smtp

import (
	"context"
	"github.com/avast/retry-go/v4"
	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/config"
	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/model/esender"
	"net/mail"
	_ "net/mail"
	"net/smtp"
	"time"
)

type client struct {
	host          string
	port          string
	auth          smtp.Auth
	retryAttempts int
	retryMaxDelay time.Duration
}

func NewClient(cfg config.SMTPServer) *client {
	return &client{
		host:          cfg.Host,
		port:          cfg.Port,
		auth:          smtp.PlainAuth(cfg.Identity, cfg.Username, cfg.Password, cfg.Host),
		retryAttempts: cfg.RetryAttempts,
		retryMaxDelay: cfg.RetryMaxDelay,
	}
}

func (c *client) SendEmail(ctx context.Context, msg esender.Message, from, replyTo mail.Address, to, cc, bcc esender.Addresses) error {
	toAddr := make([]string, 0, len(to)+len(cc)+len(bcc))
	toAddr = append(append(to.ToEmails(), cc.ToEmails()...), bcc.ToEmails()...)
	return retry.Do(func() error {
		return smtp.SendMail(c.host+":"+c.port, c.auth,
			from.Address, toAddr, msg.BuildRFC822(from, replyTo, to, cc, bcc))
	}, retry.Context(ctx), retry.Attempts(3), retry.MaxDelay(c.retryMaxDelay), retry.DelayType(retry.BackOffDelay))
}
