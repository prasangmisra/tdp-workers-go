package repository

import (
	"context"
	"errors"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/repository/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

var (
	ErrNotFound = errors.New("not found")
)

// IRepository represents basic repository functionality
type IRepository[T IDBModel] interface {
	WithTransaction(database.Database) IRepository[T]
	GetAll(context.Context, ...OptionsFunc) ([]T, error)
	GetById(context.Context, string, ...OptionsFunc) (T, error)
	Create(context.Context, T) error
	Filter(context.Context, *Filter[T], ...OptionsFunc) ([]T, error)
	Count(context.Context, *Filter[T]) (int64, error)
	Update(context.Context, T) error
}

type repository[T IDBModel] struct {
	db database.Database
}

// NewRepository creates repository
func NewRepository[T IDBModel](db database.Database) IRepository[T] {
	return &repository[T]{
		db: db,
	}
}

func (r *repository[T]) options(optFns ...OptionsFunc) *Options {
	options := &Options{
		FetchRelated: []string{},
	}

	for _, optFn := range optFns {
		optFn(options)
	}

	return options
}

// WithTransaction returns transactional repository
func (r *repository[T]) WithTransaction(db database.Database) IRepository[T] {
	return NewRepository[T](db.Begin())
}

// GetAll queries all records
func (r *repository[T]) GetAll(ctx context.Context, optFns ...OptionsFunc) (items []T, err error) {
	var t T

	tx := r.db.GetDB().WithContext(ctx).Table(t.TableName())

	tx = r.options(optFns...).apply(tx)

	err = tx.Find(&items).Error
	if err != nil {
		log.Error("error getting all records", log.Fields{
			"table":                  t.TableName(),
			types.LogFieldKeys.Error: err.Error(),
		})
		return
	}

	return
}

// Create inserts record to database
func (r *repository[T]) Create(ctx context.Context, item T) (err error) {
	tx := r.db.GetDB().WithContext(ctx)

	err = tx.Create(item).Error
	if err != nil {
		log.Error("error creating record", log.Fields{
			"table":                  item.TableName(),
			types.LogFieldKeys.Error: err.Error(),
		})
		return
	}

	return
}

// Filter queries records for provided criteria
func (r *repository[T]) Filter(ctx context.Context, filter *Filter[T], optFns ...OptionsFunc) (items []T, err error) {
	var t T

	tx := r.db.GetDB().WithContext(ctx).Table(t.TableName())

	tx = r.options(optFns...).apply(tx)

	if filter != nil {
		tx = filter.apply(tx)
	}

	err = tx.Find(&items).Error
	if err != nil {
		log.Error("error getting records", log.Fields{
			"table":                  t.TableName(),
			types.LogFieldKeys.Error: err.Error(),
		})
		return
	}

	return
}

// Count counts records for provided criteria
func (r *repository[T]) Count(ctx context.Context, filter *Filter[T]) (count int64, err error) {
	var t T

	tx := r.db.GetDB().WithContext(ctx).Table(t.TableName())

	if filter != nil {
		tx = filter.apply(tx)
	}

	err = tx.Count(&count).Error
	if err != nil {
		log.Error("error getting count of records", log.Fields{
			"table":                  t.TableName(),
			types.LogFieldKeys.Error: err.Error(),
		})
		return
	}

	return
}

// GetById gets record by id
func (r *repository[T]) GetById(ctx context.Context, id string, optFns ...OptionsFunc) (item T, err error) {
	var t T

	tx := r.db.GetDB().WithContext(ctx).Table(t.TableName())

	tx = r.options(optFns...).apply(tx)

	err = tx.First(&item, "id = ?", id).Error
	if err != nil {
		if errors.Is(err, database.ErrNotFound) {
			err = ErrNotFound
			return
		}
		log.Error("error getting record by id",
			log.Fields{
				"table":                  t.TableName(),
				"id":                     id,
				types.LogFieldKeys.Error: err.Error(),
			},
		)
		return
	}

	return
}

// Update updates record
func (r *repository[T]) Update(ctx context.Context, item T) (err error) {
	tx := r.db.GetDB().WithContext(ctx)

	err = tx.Model(item).Updates(item).Error
	if err != nil {
		log.Error("error updating record", log.Fields{
			"table":                  item.TableName(),
			types.LogFieldKeys.Error: err.Error(),
		})
	}

	return
}
