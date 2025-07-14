package repository

import (
	"fmt"

	"gorm.io/gorm"
)

// OrderDirection sorting order types
var OrderDirection = struct {
	ASC,
	DESC string
}{
	"ASC",
	"DESC",
}

// OptionsFunc func type used to provide an unified way to set query parameters
type OptionsFunc func(*Options)

// Options optional repository query parameters
type Options struct {
	TableName    string
	FetchRelated []string
}

// WithTableName used to override tale name
func WithTableName(v string) OptionsFunc {
	return func(o *Options) {
		o.TableName = v
	}
}

// WithFetchRelated used to set what related records to fetch
func WithFetchRelated(v ...string) OptionsFunc {
	return func(o *Options) {
		o.FetchRelated = v
	}
}

func (o *Options) apply(tx *gorm.DB) *gorm.DB {
	for _, fr := range o.FetchRelated {
		tx.Preload(fr)
	}

	if o.TableName != "" {
		tx = tx.Table(o.TableName)
	}

	return tx
}

// IDBModel interface represents db model
type IDBModel interface {
	TableName() string
}

// Filter filter criteria for notifications
type Filter[T IDBModel] struct {
	Model          T
	OrderBy        string
	OrderDirection string
	Limit          int
	Offset         int
}

func (f *Filter[T]) apply(tx *gorm.DB) *gorm.DB {
	if f.OrderBy != "" {
		if f.OrderDirection == OrderDirection.DESC {
			tx = tx.Order(fmt.Sprintf("%v DESC", f.OrderBy))
		} else {
			// default to ascending order
			tx = tx.Order(fmt.Sprintf("%v ASC", f.OrderBy))
		}
	}

	if f.Limit > 0 {
		tx = tx.Limit(f.Limit)
	}

	if f.Offset > 0 {
		tx = tx.Offset(f.Offset)
	}

	return tx.Where(f.Model)
}
