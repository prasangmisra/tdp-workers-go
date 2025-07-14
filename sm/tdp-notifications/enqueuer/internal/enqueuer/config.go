package enqueuer

// This code taken from:  https://github.com/tucowsinc/tdp-workers-go/tree/develop/pkg/enqueuer

import (
	"fmt"

	"github.com/tucowsinc/tdp-notifications/enqueuer/internal/types"
)

const (
	DefaultBatchSize = 100
)

type DBModel interface {
	GetID() string
	TableName() string
}

type DbEnqueuerConfig[T DBModel] struct {
	QueryExpression     string
	QueryValues         []interface{}
	UpdateFieldValueMap map[string]interface{}
	Queue               string
	BatchSize           int
	OrderByExpression   string
	OrderByDirection    types.OrderByDirection
	RawSelect           string
	Headers             map[string]any
}

type DbEnqueuerConfigBuilder[T DBModel] struct {
	config DbEnqueuerConfig[T]
}

// NewDbEnqueuerConfigBuilder creates a new builder instance
func NewDbEnqueuerConfigBuilder[T DBModel]() *DbEnqueuerConfigBuilder[T] {
	return &DbEnqueuerConfigBuilder[T]{
		config: DbEnqueuerConfig[T]{
			BatchSize: DefaultBatchSize,
		},
	}
}

// WithExplicitSelect sets the query expression for the builder
func (b *DbEnqueuerConfigBuilder[T]) WithRawSelect(expression string) *DbEnqueuerConfigBuilder[T] {
	b.config.RawSelect = expression
	return b
}

// WithQueryExpression sets the query expression for the builder
func (b *DbEnqueuerConfigBuilder[T]) WithQueryExpression(expression string) *DbEnqueuerConfigBuilder[T] {
	b.config.QueryExpression = expression
	return b
}

// WithQueryValues sets the query values for the builder
func (b *DbEnqueuerConfigBuilder[T]) WithQueryValues(values []interface{}) *DbEnqueuerConfigBuilder[T] {
	b.config.QueryValues = values
	return b
}

// WithUpdateFieldValueMap sets the update field value map for the builder
func (b *DbEnqueuerConfigBuilder[T]) WithUpdateFieldValueMap(values map[string]interface{}) *DbEnqueuerConfigBuilder[T] {
	b.config.UpdateFieldValueMap = values
	return b
}

// WithQueue sets the queue name for the builder
func (b *DbEnqueuerConfigBuilder[T]) WithQueue(queue string) *DbEnqueuerConfigBuilder[T] {
	b.config.Queue = queue
	return b
}

// WithHeaders sets the headers for the builder.  These headers will be appended to every message publish
func (b *DbEnqueuerConfigBuilder[T]) WithHeaders(headers map[string]any) *DbEnqueuerConfigBuilder[T] {
	b.config.Headers = headers
	return b
}

// WithBatchSize sets the batch size for the builder
func (b *DbEnqueuerConfigBuilder[T]) WithBatchSize(size int) *DbEnqueuerConfigBuilder[T] {
	b.config.BatchSize = size
	return b
}

// WithOrderByExpression Add a new method to set the OrderByExpression field
func (b *DbEnqueuerConfigBuilder[T]) WithOrderByExpression(orderByExpression string) *DbEnqueuerConfigBuilder[T] {
	b.config.OrderByExpression = orderByExpression
	return b
}

func (b *DbEnqueuerConfigBuilder[T]) WithOrderByDirection(direction types.OrderByDirection) *DbEnqueuerConfigBuilder[T] {
	b.config.OrderByDirection = direction
	return b
}

// Build constructs the final dbEnqueuerConfig object and checks for errors
func (b *DbEnqueuerConfigBuilder[T]) Build() (*DbEnqueuerConfig[T], error) {
	if b.config.Queue == "" {
		return nil, fmt.Errorf("queue is required")
	}
	if b.config.BatchSize < DefaultBatchSize {
		return nil, fmt.Errorf("BatchSize must be greater than or equal to %v", DefaultBatchSize)
	}

	return &b.config, nil
}
