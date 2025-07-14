package model

import (
	"encoding/json"
	"fmt"
	"github.com/jmoiron/sqlx/types"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
)

func SubscriptionFromProto(req *subscription.SubscriptionCreateRequest, tenantID string) (_ *Subscription, err error) {
	if req == nil {
		return nil, nil
	}

	var metadata types.JSONText

	metadata, err = json.Marshal(req.Metadata)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal metadata from request: %w", err)
	}

	return &Subscription{
		Descr:             req.Description,
		TenantID:          tenantID,
		TenantCustomerID:  &req.TenantCustomerId,
		NotificationEmail: req.NotificationEmail,
		Tags:              req.Tags,
		Metadata:          &metadata,
	}, nil
}
