package model

import (
	"github.com/samber/lo"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
)

var (
	SubscriptionStatus_Active      = "active"
	SubscriptionStatus_Paused      = "paused"
	SubscriptionStatus_Degraded    = "degraded"
	SubscriptionStatus_Deactivated = "deactivated"
)

var SubscriptionStatusFromProto = map[subscription.SubscriptionStatus]string{
	subscription.SubscriptionStatus_ACTIVE:      SubscriptionStatus_Active,
	subscription.SubscriptionStatus_PAUSED:      SubscriptionStatus_Paused,
	subscription.SubscriptionStatus_DEGRADED:    SubscriptionStatus_Degraded,
	subscription.SubscriptionStatus_DEACTIVATED: SubscriptionStatus_Deactivated,
}

var SubscriptionStatusToProto = lo.Invert(SubscriptionStatusFromProto)
