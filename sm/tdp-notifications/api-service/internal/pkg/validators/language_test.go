package validators

import (
	"testing"

	"github.com/go-playground/validator/v10"
	"github.com/stretchr/testify/assert"
)

func TestLanguage(t *testing.T) {
	type testItem struct {
		Language string `validate:"language"`
	}

	validate := validator.New()
	err := validate.RegisterValidation("language", validateLanguage)
	assert.NoError(t, err)

	testCases := []struct {
		test  testItem
		valid bool
	}{
		{
			test:  testItem{Language: "en"},
			valid: true,
		},
		{
			test:  testItem{Language: "de"},
			valid: true,
		},
		{
			test:  testItem{Language: "DE"},
			valid: true,
		},
		{
			test:  testItem{Language: "ar"},
			valid: false,
		},
		{
			test:  testItem{Language: ""},
			valid: false,
		},
		{
			test:  testItem{Language: "10"},
			valid: false,
		},
	}
	for _, tc := range testCases {
		err := validate.Struct(tc.test)
		assert.Equal(t, err == nil, tc.valid)
	}
}
