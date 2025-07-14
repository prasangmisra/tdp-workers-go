package service

import (
	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
)

type Service struct {
	bus           messagebus.MessageBus
	subscriptionQ string
}

func New(bus messagebus.MessageBus, subscriptionQ string) *Service {
	return &Service{
		bus:           bus,
		subscriptionQ: subscriptionQ,
	}
}
