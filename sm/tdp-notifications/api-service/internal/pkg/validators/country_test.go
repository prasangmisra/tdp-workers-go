package validators

import (
	"github.com/go-playground/validator/v10"
	"github.com/stretchr/testify/assert"
	"testing"
)

func TestCountry(t *testing.T) {
	type testItem struct {
		Country string `validate:"country"`
	}

	validate := validator.New()
	err := validate.RegisterValidation("country", validateCountry)
	assert.NoError(t, err)

	testCases := []struct {
		test  testItem
		valid bool
	}{
		{
			test:  testItem{Country: "Ca"},
			valid: true,
		},
		{
			test:  testItem{Country: "ca"},
			valid: true,
		},
		{
			test:  testItem{Country: "USA"},
			valid: false,
		},
		{
			test:  testItem{Country: "ac"},
			valid: false,
		},
		{
			test:  testItem{Country: ""},
			valid: false,
		},
		{
			test:  testItem{Country: "10"},
			valid: false,
		},
	}
	for _, tc := range testCases {
		err := validate.Struct(tc.test)
		assert.Equal(t, err == nil, tc.valid)
	}
}
