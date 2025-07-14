package models

import (
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
)

type SubscriptionStatus string // @name SubscriptionStatus

const (
	Active      SubscriptionStatus = "ACTIVE"
	Paused      SubscriptionStatus = "PAUSED"
	Degraded    SubscriptionStatus = "DEGRADED"
	Deactivated SubscriptionStatus = "DEACTIVATED"
)

var (
	subscriptionStatusFromProto = map[subscription.SubscriptionStatus]SubscriptionStatus{
		subscription.SubscriptionStatus_ACTIVE:      Active,
		subscription.SubscriptionStatus_PAUSED:      Paused,
		subscription.SubscriptionStatus_DEGRADED:    Degraded,
		subscription.SubscriptionStatus_DEACTIVATED: Deactivated,
	}
)
