package rest_client

import (
	"encoding/json"
	"reflect"
	"sync"

	"github.com/go-resty/resty/v2"
	"github.com/pkg/errors"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

var lock = sync.Mutex{}
var clientInstance *resty.Client

type RestClient[TResponse, TError interface{}] struct {
	client  *resty.Client
	request *resty.Request
}

// getClientInstance provides a singleton instance of the *resty.Client object.
// This prevents re-initializing the http client if already initialized
func getClientInstance(enableDebug bool) *resty.Client {
	if clientInstance == nil {
		lock.Lock()
		defer lock.Unlock()

		if clientInstance == nil {
			log.Debug("Creating http client instance")
			clientInstance = resty.New().SetDebug(enableDebug)
		}
	}
	return clientInstance
}

// CreateClient creates a new instance of the RestClient with typed parameters.
// Type argument TResponse represents the type of object into which a successful response will be de-serialized
// Type argument TError represents the type of object into which an un-successful response will be de-serialized
func CreateClient[TResponse, TError interface{}](enableDebug bool) *RestClient[TResponse, TError] {
	return &RestClient[TResponse, TError]{
		client: getClientInstance(enableDebug),
	}
}

// NewApiRequest creates an instance of ApiRequest object that will be passed to the `Execute` method
func (rc *RestClient[TResponse, TError]) NewApiRequest(url string, method HTTPMethod) *ApiRequest {
	return &ApiRequest{
		url:    url,
		method: method,
	}
}

// Execute method executes the http request. It returns an object or ApiResponse or an error
func (rc *RestClient[TResponse, TError]) Execute(request *ApiRequest) (response *ApiResponse[TResponse, TError], err error) {

	if request == nil {
		return nil, errors.New("Empty or nil api request. Please call 'NewApiRequest' method to create a new api request")
	}

	rc.initializeRequest(request)

	result, err := rc.request.Send()
	if err != nil {
		return nil, err
	}

	response, err = newApiResponse[TResponse, TError](result)

	return
}

func newApiResponse[TResponse, TError interface{}](r *resty.Response) (*ApiResponse[TResponse, TError], error) {
	apiResponse := &ApiResponse[TResponse, TError]{
		StatusCode: r.StatusCode(),
		IsSuccess:  r.IsSuccess(),
	}

	if r.IsSuccess() {
		var response = new(TResponse)
		if err := json.Unmarshal(r.Body(), response); err != nil {
			return nil, errors.Wrapf(err, "Unable to deserialize response into type: %v", reflect.TypeOf(response))
		}

		apiResponse.Body = response
		return apiResponse, nil
	}

	var errorResponse = new(TError)
	if err := json.Unmarshal(r.Body(), errorResponse); err != nil {
		return nil, errors.Wrapf(err, "Unable to deserialize error response into type: %v", reflect.TypeOf(errorResponse))
	}

	apiResponse.Error = errorResponse
	return apiResponse, nil
}

func (rc *RestClient[TResponse, TError]) initializeRequest(r *ApiRequest) {
	rc.request = rc.client.R().EnableTrace()

	rc.request.URL = r.url
	rc.request.Method = r.method.String()

	if r.headers != nil {
		rc.request.SetHeaders(r.headers)
	}

	if r.queryParams != nil {
		rc.request.SetQueryParams(r.queryParams)
	}

	if r.pathParams != nil {
		rc.request.SetPathParams(r.pathParams)
	}

	if r.body != nil {
		rc.request.SetBody(r.body)
	}
}
