package repository

import (
	"context"

	"github.com/stretchr/testify/mock"
	"github.com/tucowsinc/tdp-workers-go/pkg/repository/database"
)

type MockRepository[T IDBModel] struct {
	mock.Mock
	IRepository[T]
}

func (mr *MockRepository[T]) WithTransaction(db database.Database) IRepository[T] {
	args := mr.Called(db)
	if args.Get(0) != nil {
		return args.Get(0).(*MockRepository[T])
	}

	return nil
}

func (mr *MockRepository[T]) Create(ctx context.Context, item T) (err error) {
	args := mr.Called(ctx, item)
	err = args.Error(1)
	return
}

func (mr *MockRepository[T]) Filter(ctx context.Context, filter *Filter[T], optFns ...OptionsFunc) (items []T, err error) {
	args := mr.Called(ctx, filter)
	if args.Get(0) != nil {
		items = args.Get(0).([]T)
	}

	err = args.Error(1)
	return
}

func (mr *MockRepository[T]) Count(ctx context.Context, filter *Filter[T]) (count int64, err error) {
	args := mr.Called(ctx, filter)
	if args.Get(0) != nil {
		count = args.Get(0).(int64)
	}

	err = args.Error(1)
	return
}

func (mr *MockRepository[T]) GetById(ctx context.Context, id string, optFns ...OptionsFunc) (item T, err error) {
	args := mr.Called(ctx, id)
	if args.Get(0) != nil {
		item = args.Get(0).(T)
	}

	err = args.Error(1)
	return
}

func (mr *MockRepository[T]) Update(ctx context.Context, item T) (err error) {
	args := mr.Called(ctx, item)
	err = args.Error(0)
	return
}

type MockLookupTable[T ILookupModel] struct {
	mock.Mock
	ILookupTable[T]
}

func (me *MockLookupTable[T]) GetNameById(id string) string {
	args := me.Called(id)

	if args.Get(0) != nil {
		return args.Get(0).(string)
	}

	return ""
}

func (me *MockLookupTable[T]) GetIdByName(name string) string {
	args := me.Called(name)

	if args.Get(0) != nil {
		return args.Get(0).(string)
	}

	return ""
}
