package sqs

import (
	"context"
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSqsOptionsBuilderSSOProfile(t *testing.T) {
	queueName := "test-queue"
	ssoProfileName := "test-sso-profile"

	ob := NewOptionsBuilder()
	assert.NotNil(t, ob)

	options, err := ob.WithQueueName(queueName).
		WithSSOProfileName(ssoProfileName).
		WithDebugModeEnabled(true).
		Build()

	assert.NoError(t, err)

	assert.Equal(t, options.QueueName, queueName)
	assert.Equal(t, options.SSOProfileName, ssoProfileName)
	assert.True(t, options.EnableDebugMode)
}

func TestSqsOptionsBuilderCreds(t *testing.T) {
	queueName := "test-queue"
	accessKeyId := "test-access-key"
	secretAccessKey := "test-secret-id"
	sessionToken := "test-session-token"
	region := "test-region"
	arn := "arn:test"
	sessionName := "test-session-name"
	roles := fmt.Sprintf("[{\"arn\":\"%v\",\"session_name\":\"%v\"}]", arn, sessionName)

	ob := NewOptionsBuilder()
	assert.NotNil(t, ob)

	options, err := ob.WithQueueName(queueName).
		WithDebugModeEnabled(true).
		WithAccessKeyId(accessKeyId).
		WithSecretAccessKey(secretAccessKey).
		WithSessionToken(sessionToken).
		WithRegion(region).
		WithRoles(roles).
		Build()

	assert.NoError(t, err)

	assert.Equal(t, options.QueueName, queueName)
	assert.True(t, options.EnableDebugMode)
	assert.Equal(t, options.AccessKeyId, accessKeyId)
	assert.Equal(t, options.SecretAccessKey, secretAccessKey)
	assert.Equal(t, options.SessionToken, sessionToken)
	assert.Equal(t, options.Region, region)
	assert.Equal(t, options.Roles, []AWSRole{{
		Arn:         arn,
		SessionName: sessionName,
	}})
}

func TestSqsOptionsBuilder__Failure(t *testing.T) {
	ob := NewOptionsBuilder()
	assert.NotNil(t, ob)

	options, err := ob.WithQueueName("").
		Build()

	assert.Nil(t, options)

	assert.ErrorContains(t, err, "queueName must be provided")
}

func TestSqsOptionsLoadConfiguration(t *testing.T) {
	queueName := "test-queue"
	accessKeyId := "test-access-key"
	secretAccessKey := "test-secret-id"
	sessionToken := "test-session-token"
	region := "test-region"

	ob := NewOptionsBuilder()
	assert.NotNil(t, ob)

	options, err := ob.WithQueueName(queueName).
		WithDebugModeEnabled(true).
		WithAccessKeyId(accessKeyId).
		WithSecretAccessKey(secretAccessKey).
		WithSessionToken(sessionToken).
		WithRegion(region).
		Build()

	assert.NoError(t, err)

	cfg, err := options.LoadConfiguration(context.Background())

	assert.NoError(t, err)

	creds, err := cfg.Credentials.Retrieve(context.Background())

	assert.NoError(t, err)

	assert.Equal(t, creds.AccessKeyID, accessKeyId)
	assert.Equal(t, creds.SecretAccessKey, secretAccessKey)
	assert.Equal(t, creds.SessionToken, sessionToken)
}
