package sqs

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/credentials/stscreds"
	sqstypes "github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"github.com/aws/aws-sdk-go-v2/service/sts"
	"github.com/pkg/errors"
	"github.com/tucowsinc/tdp-messages-go/message"
	"google.golang.org/protobuf/proto"
)

const DefaultNumReceivers = 25

type AWSRole struct {
	Arn         string `json:"arn"`
	SessionName string `json:"session_name"`
}

// SqsOptions represents the configuration options required to configure SQS
type SqsOptions struct {
	QueueName       string
	QueueAccountId  string
	SSOProfileName  string
	ClientAPI       SQSClientAPI
	EnableDebugMode bool
	AccessKeyId     string
	SecretAccessKey string
	SessionToken    string
	Region          string
	Roles           []AWSRole
	NumReceivers    int
}

// LoadConfiguration loads aws configuration according to provided options
func (o *SqsOptions) LoadConfiguration(ctx context.Context) (cfg aws.Config, err error) {
	var optFns []func(*config.LoadOptions) error

	if o.SSOProfileName != "" {
		optFns = append(optFns, config.WithSharedConfigProfile(o.SSOProfileName))

	} else if o.AccessKeyId != "" && o.SecretAccessKey != "" {
		creds := aws.Credentials{
			AccessKeyID:     o.AccessKeyId,
			SecretAccessKey: o.SecretAccessKey,
		}

		// temporary credentials might include session token
		if o.SessionToken != "" {
			creds.SessionToken = o.SessionToken
		}

		optFns = append(
			optFns,
			config.WithCredentialsProvider(credentials.StaticCredentialsProvider{Value: creds}),
		)
	}

	if o.Region != "" {
		optFns = append(optFns, config.WithDefaultRegion(o.Region))
	}

	cfg, err = config.LoadDefaultConfig(ctx, optFns...)
	if err != nil {
		return
	}

	for _, role := range o.Roles {
		creds := stscreds.NewAssumeRoleProvider(
			sts.NewFromConfig(cfg),
			role.Arn,
			func(opts *stscreds.AssumeRoleOptions) {
				opts.RoleSessionName = role.SessionName
			},
		)

		cfg.Credentials = aws.NewCredentialsCache(creds)
	}

	if o.EnableDebugMode {
		cfg.ClientLogMode = aws.LogRequestWithBody | aws.LogResponseWithBody
	}

	return
}

// SqsOptionsBuilder provides a mechanism to validate and build SqsOptions
type SqsOptionsBuilder struct {
	Options *SqsOptions
	errors  []error
}

type sqsConsumer struct {
	ctx          context.Context
	client       SQSClientAPI
	options      *SqsOptions
	queueUrl     *string
	sqsMessages  chan sqstypes.Message
	wireMessages chan *message.TcWire
	handlers     map[string]handlerType
}

type sqsPublisher struct {
	ctx      context.Context
	client   SQSClientAPI
	queueUrl *string
	options  *SqsOptions
}

// Server is representation of current message processing state
type Server struct {
	Ctx      context.Context
	Envelope *message.TcWire
	Headers  map[string]any
}

// HandlerFuncType a type for all message handler functions registered with message type
type HandlerFuncType func(Server, proto.Message) (err error)

// HandlerType this is the handler to be used when registering a new
// service
type handlerType struct {
	Handler     HandlerFuncType // callback function to call with payload
	messageType interface{}     // this holds a variable of the expected message type
}

// NewOptionsBuilder creates a new instance of SqsOptionsBuilder
func NewOptionsBuilder() *SqsOptionsBuilder {
	return &SqsOptionsBuilder{Options: &SqsOptions{}}
}

// WithQueueName configures the SqsOptions with SQS queue name
func (ob *SqsOptionsBuilder) WithQueueName(queueName string) *SqsOptionsBuilder {
	if queueName == "" {
		ob.errors = append(ob.errors, errors.New("queueName must be provided"))
	}

	ob.Options.QueueName = queueName
	return ob
}

// WithQueueAccountId configures the SqsOptions with SQS queue account id
func (ob *SqsOptionsBuilder) WithQueueAccountId(queueAccountId string) *SqsOptionsBuilder {
	ob.Options.QueueAccountId = queueAccountId
	return ob
}

// WithSSOProfileName configures sso profile to use for SQS authentication
func (ob *SqsOptionsBuilder) WithSSOProfileName(ssoProfileName string) *SqsOptionsBuilder {
	ob.Options.SSOProfileName = ssoProfileName
	return ob
}

// WithAccessKeyId configures access key id to use for SQS authentication
func (ob *SqsOptionsBuilder) WithAccessKeyId(accessKeyId string) *SqsOptionsBuilder {
	ob.Options.AccessKeyId = accessKeyId
	return ob
}

// WithSecretAccessKey configures secret access key to use for SQS authentication
func (ob *SqsOptionsBuilder) WithSecretAccessKey(secretAccessKey string) *SqsOptionsBuilder {
	ob.Options.SecretAccessKey = secretAccessKey
	return ob
}

// WithSessionToken configures session token to use for SQS authentication
func (ob *SqsOptionsBuilder) WithSessionToken(sessionToken string) *SqsOptionsBuilder {
	ob.Options.SessionToken = sessionToken
	return ob
}

// WithRegion configures session token to use for SQS authentication
func (ob *SqsOptionsBuilder) WithRegion(region string) *SqsOptionsBuilder {
	ob.Options.Region = region
	return ob
}

// WithRoles parses and sets aws roles
func (ob *SqsOptionsBuilder) WithRoles(roles string) *SqsOptionsBuilder {
	if roles != "" {
		err := json.Unmarshal([]byte(roles), &ob.Options.Roles)
		if err != nil {
			ob.errors = append(ob.errors, fmt.Errorf("error parsing AWS roles: %v", err))
		}
	}

	return ob
}

// WithDebugModeEnabled configures request and response body logging for SQS operations
func (ob *SqsOptionsBuilder) WithDebugModeEnabled(enable bool) *SqsOptionsBuilder {
	ob.Options.EnableDebugMode = enable
	return ob
}

// WithSQSClientAPI configures custom sqs client api
func (ob *SqsOptionsBuilder) WithSQSClientAPI(client SQSClientAPI) *SqsOptionsBuilder {
	ob.Options.ClientAPI = client
	return ob
}

// WithNumReceivers configures number of receivers handling incoming
func (ob *SqsOptionsBuilder) WithNumReceivers(num int) *SqsOptionsBuilder {
	if num <= 0 {
		ob.errors = append(ob.errors, errors.New("num must be positive non-zero value"))
	}

	ob.Options.NumReceivers = num
	return ob
}

// Build provides a validated and configured instance of SqsOptions
func (ob *SqsOptionsBuilder) Build() (*SqsOptions, error) {

	if len(ob.errors) > 0 {
		var errorMessages []string
		for _, err := range ob.errors {
			errorMessages = append(errorMessages, err.Error())
		}
		return nil, fmt.Errorf("validation errors:\n%s", strings.Join(errorMessages, "\n"))
	}

	if ob.Options.NumReceivers == 0 {
		ob.Options.NumReceivers = DefaultNumReceivers
	}

	return ob.Options, nil
}
