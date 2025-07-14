package models

import (
	"errors"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-messages-go/message/subscription"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// Mock HTTP Head function for success
func mockHTTPHeadSuccess(url string) (*http.Response, error) {
	return &http.Response{
		StatusCode: http.StatusOK,
		Body:       http.NoBody, // No body required for HEAD request
	}, nil
}

// Mock HTTP Head function for failure
func mockHTTPHeadFailure(url string) (*http.Response, error) {
	return nil, errors.New("mocked error")
}

func TestSubscriptionFromProtoHelper(t *testing.T) {
	now := time.Now().UTC()
	// Helper function to convert metadata map to proto safely
	metadataToProtoSafe := func(t *testing.T, metadata map[string]interface{}) map[string]*anypb.Any {
		protoMetadata, err := MetadataToProto(metadata)
		require.NoError(t, err)
		return protoMetadata
	}

	metadata := map[string]interface{}{"key1": "value1"}
	metadataProto := metadataToProtoSafe(t, metadata)
	description := stringPtr("Test Subscription")
	tests := []struct {
		name     string
		input    *subscription.SubscriptionDetailsResponse
		expected *Subscription
	}{
		{
			name: "valid input",
			input: &subscription.SubscriptionDetailsResponse{
				Id:                "123",
				NotificationEmail: "test@example.com",
				Url:               "https://example.com",
				Description:       description,
				Tags:              []string{"tag1", "tag2"},
				Metadata:          metadataProto,
				Status:            subscription.SubscriptionStatus_ACTIVE,
				NotificationTypes: []string{"DOMAIN_CREATED"},
				CreatedDate:       timestamppb.New(now),
				UpdatedDate:       timestamppb.New(now),
			},
			expected: &Subscription{
				ID:                "123",
				NotificationEmail: "test@example.com",
				URL:               "https://example.com",
				Description:       description,
				Tags:              []string{"tag1", "tag2"},
				Metadata:          metadata,
				Status:            subscriptionStatusFromProto[subscription.SubscriptionStatus_ACTIVE],
				NotificationTypes: []string{"DOMAIN_CREATED"},
				CreatedDate:       &now,
				UpdatedDate:       &now,
			},
		},
		{
			name:     "nil input",
			input:    nil,
			expected: nil,
		},
		{
			name: "missing optional fields",
			input: &subscription.SubscriptionDetailsResponse{
				Id:                "123",
				NotificationEmail: "test@example.com",
				Url:               "https://example.com",
				Status:            subscription.SubscriptionStatus_DEGRADED,
			},
			expected: &Subscription{
				ID:                "123",
				NotificationEmail: "test@example.com",
				URL:               "https://example.com",
				Status:            subscriptionStatusFromProto[subscription.SubscriptionStatus_DEGRADED],
				NotificationTypes: []string{},
				Tags:              []string{},
				Metadata:          make(map[string]interface{}),
				CreatedDate:       nil,
				UpdatedDate:       nil,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := subscriptionFromProtoHelper(tt.input)
			if tt.expected != nil && result != nil {
				assert.Equal(t, tt.expected.ID, result.ID)
				assert.Equal(t, tt.expected.NotificationEmail, result.NotificationEmail)
				assert.Equal(t, tt.expected.URL, result.URL)
				assert.Equal(t, tt.expected.Description, result.Description)
				assert.Equal(t, tt.expected.Status, result.Status)

				// These treat nil and empty slices/maps as equal
				assert.ElementsMatch(t, tt.expected.Tags, result.Tags)                           // Handles slice comparison
				assert.ElementsMatch(t, tt.expected.NotificationTypes, result.NotificationTypes) // Handles slice comparison
				// Handle comparison of nil vs empty map for Metadata
				if len(tt.expected.Metadata) == 0 && result.Metadata == nil {
					// Treat nil and empty map as equal
					assert.Nil(t, result.Metadata)
				} else {
					assert.Equal(t, tt.expected.Metadata, result.Metadata)
				}

				assert.Equal(t, tt.expected.CreatedDate, result.CreatedDate)
				assert.Equal(t, tt.expected.UpdatedDate, result.UpdatedDate)
			}
		})
	}
}

func stringPtr(s string) *string {
	if s != "" {
		return &s
	}
	return nil
}

func TestMetadataFromProto(t *testing.T) {
	t.Parallel()

	// Helper function to handle errors in proto conversion
	anyProto := func(t *testing.T, value proto.Message) *anypb.Any {
		protoValue, err := anypb.New(value)
		require.NoError(t, err)
		return protoValue
	}

	tests := []struct {
		name           string
		protoMetadata  map[string]*anypb.Any
		expectedOutput map[string]interface{}
	}{
		{
			name:           "Proto metadata is nil",
			protoMetadata:  nil,
			expectedOutput: nil,
		},
		{
			name: "Proto metadata has string value",
			protoMetadata: map[string]*anypb.Any{
				"stringKey": anyProto(t, structpb.NewStringValue("testValue")),
			},
			expectedOutput: map[string]interface{}{
				"stringKey": "testValue",
			},
		},
		{
			name: "Proto metadata has number value",
			protoMetadata: map[string]*anypb.Any{
				"numberKey": anyProto(t, structpb.NewNumberValue(123.45)),
			},
			expectedOutput: map[string]interface{}{
				"numberKey": 123.45,
			},
		},
		{
			name: "Proto metadata has int value",
			protoMetadata: map[string]*anypb.Any{
				"intKey": anyProto(t, structpb.NewNumberValue(123)),
			},
			expectedOutput: map[string]interface{}{
				"intKey": float64(123), // structpb.NumberValue always returns float64
			},
		},
		{
			name: "Proto metadata has boolean value",
			protoMetadata: map[string]*anypb.Any{
				"boolKey": anyProto(t, structpb.NewBoolValue(true)),
			},
			expectedOutput: map[string]interface{}{
				"boolKey": true,
			},
		},
		{
			name: "Proto metadata has null value",
			protoMetadata: map[string]*anypb.Any{
				"nullKey": anyProto(t, structpb.NewNullValue()),
			},
			expectedOutput: map[string]interface{}{
				"nullKey": nil,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			convertedMetadata := MetadataFromProto(tt.protoMetadata)
			assert.Equal(t, tt.expectedOutput, convertedMetadata)
		})
	}
}

func TestMetadataToProto(t *testing.T) {
	t.Parallel()

	// Helper function to handle errors in proto conversion
	anyProto := func(t *testing.T, value proto.Message) *anypb.Any {
		protoValue, err := anypb.New(value)
		require.NoError(t, err)
		return protoValue
	}

	// Helper function to create a structpb.Value safely
	structProto := func(t *testing.T, v interface{}) *structpb.Value {
		structValue, err := structpb.NewValue(v)
		require.NoError(t, err)
		return structValue
	}

	tests := []struct {
		name           string
		mapMetadata    map[string]interface{}
		expectedOutput map[string]*anypb.Any
	}{
		{
			name: "Map metadata has values",
			mapMetadata: map[string]interface{}{
				"testKey": "testValue",
			},
			expectedOutput: map[string]*anypb.Any{
				"testKey": anyProto(t, structProto(t, "testValue")),
			},
		},
		{
			name:           "Map metadata is nil",
			mapMetadata:    nil,
			expectedOutput: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			convertedMetadata, err := MetadataToProto(tt.mapMetadata)
			require.NoError(t, err, "MetadataToProto should not return an error")
			assert.Equal(t, tt.expectedOutput, convertedMetadata)
		})
	}
}
