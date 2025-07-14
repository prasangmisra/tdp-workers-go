package enumerator

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/assert"
	"gorm.io/gorm"
)

type TestEnumerator struct{}

func (*TestEnumerator) Enumerate(*gorm.DB) (data map[string]string, err error) {
	data = map[string]string{
		"Name1": "Id1",
		"Name2": "Id2",
		"Name3": "Id3",
	}

	return
}

type TestBadEnumerator struct{}

func (*TestBadEnumerator) Enumerate(*gorm.DB) (data map[string]string, err error) {
	err = errors.New("failed to get data")
	return
}

func TestEnum(t *testing.T) {
	et, err := New[*TestEnumerator](&gorm.DB{})

	assert.Nil(t, err)
	assert.IsType(t, (*EnumTable[*TestEnumerator])(nil), &et)

	assert.Equal(t, et.GetByKey("Name1"), "Id1")
	assert.Equal(t, et.GetByValue("Id1"), "Name1")
}

func TestEnumNoKeyValue(t *testing.T) {
	et, err := New[*TestEnumerator](&gorm.DB{})

	assert.Nil(t, err)

	assert.Zero(t, et.GetByKey("DoesNotExist"))
	assert.Zero(t, et.GetByValue("DoesNotExist"))
}

func TestEnumError(t *testing.T) {
	_, err := New[*TestBadEnumerator](&gorm.DB{})

	assert.EqualError(t, err, "failed to get data")
}
