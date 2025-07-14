package validators

import (
	"errors"
	"net/http"
	"testing"

	"github.com/go-playground/validator/v10"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/config"
)

// Mock HTTP Head function for success
func mockHTTPHeadSuccess(url string) (*http.Response, error) {
	return &http.Response{
		StatusCode: http.StatusOK,
		Body:       http.NoBody, // No body required for HEAD request
	}, nil
}

// Mock HTTP Head function for failure
func mockHTTPHeadFailure(url string) (*http.Response, error) {
	return nil, errors.New("mocked error")
}

func TestURLReachable(t *testing.T) {
	type testItem struct {
		URL string `validate:"url_reachable"`
	}
	validate := validator.New()
	var cfg config.Config

	testCases := []struct {
		test             testItem
		mockHTTPHeadFunc func(string) (*http.Response, error)
		errAssertion     require.ErrorAssertionFunc
		testValidation   bool
	}{
		{
			test:             testItem{URL: "https://randomurl.com"},
			mockHTTPHeadFunc: mockHTTPHeadFailure,
			errAssertion:     require.Error,
			testValidation:   true,
		},
		{
			test:             testItem{URL: "https://tucows.com"},
			mockHTTPHeadFunc: mockHTTPHeadSuccess,
			errAssertion:     require.NoError,
			testValidation:   true,
		},
		{
			test:             testItem{URL: "https://randomurl.com"},
			mockHTTPHeadFunc: mockHTTPHeadFailure,
			errAssertion:     require.NoError,
			testValidation:   false,
		},
		{
			test:             testItem{URL: "https://tucows.com"},
			mockHTTPHeadFunc: mockHTTPHeadSuccess,
			errAssertion:     require.NoError,
			testValidation:   false,
		},
	}

	for _, tc := range testCases {
		HttpHeadFunc = tc.mockHTTPHeadFunc
		cfg.Validator.UrlReachability = tc.testValidation
		err := validate.RegisterValidation("url_reachable", urlReachable(&cfg))
		assert.NoError(t, err)
		tc.errAssertion(t, validate.Struct(tc.test))
	}
}

func TestURLReachable_InvalidType(t *testing.T) {
	type testItem struct {
		URL int `validate:"url_reachable"` // Invalid type: int instead of string
	}
	validate := validator.New()
	var cfg config.Config

	testCases := []struct {
		test           testItem
		errAssertion   require.ErrorAssertionFunc
		testValidation bool
	}{
		{
			test:           testItem{URL: 12345}, // Invalid type for URL
			errAssertion:   require.Error,
			testValidation: true,
		},
		{
			test:           testItem{URL: 12345}, // Invalid type for URL
			errAssertion:   require.NoError,
			testValidation: false,
		},
	}

	for _, tc := range testCases {
		cfg.Validator.UrlReachability = tc.testValidation
		err := validate.RegisterValidation("url_reachable", urlReachable(&cfg))
		assert.NoError(t, err)
		tc.errAssertion(t, validate.Struct(tc.test))
	}
}
