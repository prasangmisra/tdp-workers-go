package enumerator

import (
	"github.com/vishalkuo/bimap"
	"gorm.io/gorm"
)

// Enumerator interface which should be implemented by type to be used as enum table
type Enumerator interface {
	Enumerate(*gorm.DB) (map[string]string, error)
}

// EnumTable provides 2 way map created from enumerator
type EnumTable[T Enumerator] struct {
	data *bimap.BiMap[string, string]
}

// New creates enum table using enumerator type and db connection
func New[T Enumerator](tx *gorm.DB) (et EnumTable[T], err error) {
	var enumerator T

	data, err := enumerator.Enumerate(tx)
	if err != nil {
		return
	}

	et = EnumTable[T]{
		data: bimap.NewBiMapFromMap(data),
	}

	return
}

// GetByKey returns value on hit or empty string on miss
func (et *EnumTable[T]) GetByKey(key string) (value string) {
	value, _ = et.data.Get(key)
	return
}

// GetByValue returns key on hit or empty string on miss
func (et *EnumTable[T]) GetByValue(value string) (key string) {
	key, _ = et.data.GetInverse(value)
	return
}
