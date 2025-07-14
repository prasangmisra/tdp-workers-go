package repository

import (
	"context"

	"github.com/tucowsinc/tdp-workers-go/pkg/repository/database"
	"github.com/vishalkuo/bimap"
)

// ILookupModel represents model that can be used as lookup table
type ILookupModel interface {
	IDBModel
	GetID() string
	GetName() string
}

// ILookupTable represents basic lookup functionality
type ILookupTable[T ILookupModel] interface {
	GetNameById(string) string
	GetIdByName(string) string
}

type lookupTable[T ILookupModel] struct {
	data *bimap.BiMap[string, string]
}

// NewLookupTable creates lookup table instance
func NewLookupTable[T ILookupModel](db database.Database) (e ILookupTable[T], err error) {
	repo := NewRepository[T](db)
	data := make(map[string]string)

	items, err := repo.GetAll(context.Background())
	if err != nil {
		return
	}

	for _, item := range items {
		data[item.GetName()] = item.GetID()
	}

	e = &lookupTable[T]{
		data: bimap.NewBiMapFromMap(data),
	}

	return
}

// GetNameById returns name by id
func (e *lookupTable[T]) GetNameById(id string) string {
	name, _ := e.data.GetInverse(id)
	return name
}

// GetIdByName returns id by name
func (e *lookupTable[T]) GetIdByName(name string) string {
	id, _ := e.data.Get(name)
	return id
}
