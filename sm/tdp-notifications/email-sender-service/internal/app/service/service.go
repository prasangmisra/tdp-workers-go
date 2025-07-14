package service

import (
	"context"
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"github.com/tucowsinc/tdp-notifications/email-sender-service/internal/app/model/esender"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"net/mail"
)

//go:generate mockery --name iEmailSender --output ../mocks/ --outpkg mocks --structname EmailSender
type iEmailSender interface {
	SendEmail(ctx context.Context, msg esender.Message, from, replyTo mail.Address, to, cc, bcc esender.Addresses) error
}
type service struct {
	logger      logger.ILogger
	emailSender iEmailSender
	bus         messagebus.MessageBus
	statusQ     string
}

// New initializes a new service instance.
func New(log logger.ILogger, emailSender iEmailSender, bus messagebus.MessageBus, statusQ string) *service {
	return &service{
		logger:      log,
		emailSender: emailSender,
		bus:         bus,
		statusQ:     statusQ,
	}
}
