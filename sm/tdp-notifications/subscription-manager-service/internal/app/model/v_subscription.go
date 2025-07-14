package model

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/jmoiron/sqlx/types"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const SubscriptionType_Webhook = "webhook"
const SubscriptionType_Poll = "poll"

func (s *VSubscription) ToProtoCreate() (*subscription.SubscriptionCreateResponse, error) {
	if s == nil {
		return nil, nil
	}

	sub, err := s.toProto()
	if err != nil {
		return nil, err
	}

	msg := &subscription.SubscriptionCreateResponse{Subscription: sub}

	if s.SigningSecret != nil {
		msg.SigningSecret = *s.SigningSecret
	}

	return msg, nil
}

func (s *VSubscription) ToProtoGet() (*subscription.SubscriptionGetResponse, error) {
	if s == nil {
		return nil, nil
	}

	sub, err := s.toProto()
	if err != nil {
		return nil, err
	}

	return &subscription.SubscriptionGetResponse{Subscription: sub}, nil
}

func (s *VSubscription) ToProtoPause() (*subscription.SubscriptionPauseResponse, error) {
	if s == nil {
		return nil, nil
	}

	sub, err := s.toProto()
	if err != nil {
		return nil, err
	}

	return &subscription.SubscriptionPauseResponse{Subscription: sub}, nil
}

func (s *VSubscription) ToProtoResume() (*subscription.SubscriptionResumeResponse, error) {
	if s == nil {
		return nil, nil
	}

	sub, err := s.toProto()
	if err != nil {
		return nil, err
	}

	return &subscription.SubscriptionResumeResponse{Subscription: sub}, nil
}

func (s *VSubscription) ToProtoUpdate() (*subscription.SubscriptionUpdateResponse, error) {
	if s == nil {
		return nil, nil
	}

	sub, err := s.toProto()
	if err != nil {
		return nil, err
	}

	return &subscription.SubscriptionUpdateResponse{Subscription: sub}, nil
}

func (s *VSubscription) toProto() (*subscription.SubscriptionDetailsResponse, error) {
	if s == nil {
		return nil, nil
	}

	var metadata map[string]*anypb.Any
	if s.Metadata != nil {
		if err := json.Unmarshal(*s.Metadata, &metadata); err != nil {
			return nil, err
		}
	}

	msg := &subscription.SubscriptionDetailsResponse{
		Id:                s.ID,
		Description:       s.Description,
		Metadata:          metadata,
		Tags:              s.Tags,
		CreatedDate:       timeToProto(s.CreatedDate),
		UpdatedDate:       timeToProto(s.UpdatedDate),
		Status:            SubscriptionStatusToProto[s.Status],
		NotificationEmail: s.NotificationEmail,
		NotificationTypes: s.Notifications,
	}

	if s.WebhookURL != nil {
		msg.Url = *s.WebhookURL
	}

	return msg, nil
}

func timeToProto(t *time.Time) *timestamppb.Timestamp {
	if t == nil {
		return nil
	}
	return timestamppb.New(*t)
}

func VSubscriptionListToProto(sList []*VSubscription, total int64) (*subscription.SubscriptionListResponse, error) {
	res := make([]*subscription.SubscriptionDetailsResponse, 0, len(sList))
	for _, s := range sList {
		r, err := s.toProto()
		if err != nil {
			return nil, err
		}
		res = append(res, r)
	}

	return &subscription.SubscriptionListResponse{Subscriptions: res, TotalCount: int32(total)}, nil
}

func VSubscriptionFromProtoUpdate(req *subscription.SubscriptionUpdateRequest) (*VSubscription, error) {
	if req == nil || req.Description == nil && len(req.NotificationEmail)+len(req.Tags)+len(req.Metadata) == 0 {
		return nil, nil
	}

	vSubscription := &VSubscription{
		ID:                req.Id,
		Description:       req.Description,
		NotificationEmail: req.NotificationEmail,
		Tags:              req.Tags,
	}

	if req.Metadata == nil {
		return vSubscription, nil
	}

	var metadata types.JSONText
	metadata, err := json.Marshal(req.Metadata)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal metadata from request: %w", err)
	}

	vSubscription.Metadata = &metadata

	return vSubscription, nil
}
