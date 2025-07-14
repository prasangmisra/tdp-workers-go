package v1_test

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http/httptest"
	"net/url"
	"sync"
	"testing"

	"github.com/lpar/problem"
	"github.com/stretchr/testify/require"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/app/handlers/rest"
	v1restmock "github.com/tucowsinc/tdp-notifications/api-service/internal/app/mocks/rest/v1"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/config"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/validators"
	"github.com/tucowsinc/tdp-shared-go/logger"
)

func buildURLWithQuery(t *testing.T, path string, queryParams map[string]string) string {
	t.Helper()

	urlParsed, err := url.Parse(path)
	require.NoError(t, err)

	values := urlParsed.Query()
	for key, value := range queryParams {
		values.Add(key, value)
	}
	urlParsed.RawQuery = values.Encode()
	return urlParsed.String()
}

func defaultHeaders(baseHeader *gcontext.BaseHeader) map[string]any {
	headers := map[string]any{
		"try-sync":    false,
		"traceparent": "",
		"tracestate":  "",
	}
	if baseHeader != nil {
		headers["tenant-customer-id"] = baseHeader.XTenantCustomerID
	}
	return headers
}

var once sync.Once

func setupValidators(t *testing.T) {
	t.Helper()
	var cfg config.Config
	cfg.Validator.HttpsUrl = true
	cfg.Validator.UrlReachability = false
	once.Do(func() {
		err := validators.RegisterValidators(&cfg)
		if err != nil {
			require.NoError(t, err, "Failed to register validators")
		}
	})
}

func serveTestHTTP[T any](t *testing.T, method, path string,
	mocksF func(s *v1restmock.IService, res any), baseHeader *gcontext.BaseHeader,
	req, expectedResp any, expectedStatus int) {
	t.Helper()

	var body io.Reader
	if req != nil {
		requestBody, err := json.Marshal(req)
		require.NoError(t, err)
		body = bytes.NewBuffer(requestBody)
	}

	httpReq := httptest.NewRequest(method, path, body)
	if baseHeader != nil {
		httpReq.Header.Set("x-tenant-customer-id", baseHeader.XTenantCustomerID)
	}
	httpReq.Header.Set("x-version", "v1")

	s := v1restmock.NewIService(t)
	router := rest.NewRouter(s, &config.Config{}, &logger.MockLogger{})

	if mocksF != nil {
		// mocked call to service should return only T
		// if we expect an error, the response from mock should be nil
		resp, _ := expectedResp.(*T)
		mocksF(s, resp)
	}

	w := httptest.NewRecorder()
	router.ServeHTTP(w, httpReq)
	httpRes := w.Result()
	defer require.NoError(t, httpRes.Body.Close())

	require.Equal(t, expectedStatus, w.Code)

	// Special case for asserting that there should be no response body
	if expectedResp == nil {
		resBody, err := io.ReadAll(httpRes.Body)
		require.NoError(t, err)
		require.Len(t, resBody, 0)
		return
	}

	var resp any
	switch expectedResp.(type) {
	case *T:
		resp = new(T)
	case *problem.ValidationProblem:
		resp = &problem.ValidationProblem{}
	default:
		resp = &problem.ProblemDetails{}
	}
	err := json.NewDecoder(httpRes.Body).Decode(resp)
	require.NoError(t, err)

	require.Equal(t, expectedResp, resp)
}
