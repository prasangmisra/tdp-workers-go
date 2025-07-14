package validators

import (
	"testing"

	"github.com/go-playground/validator/v10"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/config"
)

func TestURLValidator(t *testing.T) {
	type testItem struct {
		URL string `validate:"https_url"`
	}

	validate := validator.New()
	var cfg config.Config

	testCases := []struct {
		test           testItem
		errAssertion   require.ErrorAssertionFunc
		testValidation bool
	}{
		// Valid HTTPS URLs
		{
			test:         testItem{URL: "https://www.google.com"},
			errAssertion: require.NoError,
		},
		{
			test:         testItem{URL: "https://example.com"},
			errAssertion: require.NoError,
		},
		// Invalid URLs (not HTTPS)
		{
			test:           testItem{URL: "http://www.google.com"},
			errAssertion:   require.Error,
			testValidation: true,
		},
		{
			test:           testItem{URL: "ftp://example.com"},
			errAssertion:   require.Error,
			testValidation: true,
		},
		// Empty or malformed URLs
		{
			test:           testItem{URL: ""},
			errAssertion:   require.Error,
			testValidation: true,
		},
		{
			test:         testItem{URL: ""},
			errAssertion: require.NoError,
		},
		{
			test:           testItem{URL: "not_a_url"},
			errAssertion:   require.Error,
			testValidation: true,
		},
		{
			test:           testItem{URL: "not_a_url"},
			errAssertion:   require.NoError,
			testValidation: false,
		},
		{
			test:           testItem{URL: "http://www.google.com"},
			errAssertion:   require.NoError,
			testValidation: false,
		},
	}

	for _, tc := range testCases {
		cfg.Validator.HttpsUrl = tc.testValidation
		err := validate.RegisterValidation("https_url", urlValidator(&cfg))
		assert.NoError(t, err)
		tc.errAssertion(t, validate.Struct(tc.test))
	}
}
