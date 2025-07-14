package rest_client

type HTTPMethod int

const (
	GET HTTPMethod = iota
	POST
	PUT
	PATCH
	DELETE
)

// ApiResponse represents the response object from the rest client
type ApiResponse[TResponse, TError interface{}] struct {
	StatusCode int
	IsSuccess  bool
	Body       *TResponse
	Error      *TError
}

// ApiRequest represents the request object provided to the rest client `Execute` method
type ApiRequest struct {
	url         string
	method      HTTPMethod
	headers     map[string]string
	queryParams map[string]string
	pathParams  map[string]string

	body interface{}
}

// SetHeaders adds the provided headers to the ApiRequest
func (r *ApiRequest) SetHeaders(headers map[string]string) *ApiRequest {
	if headers == nil {
		return r
	}

	r.headers = headers
	return r
}

// SetQueryParams adds the provided query parameters to the ApiRequest
func (r *ApiRequest) SetQueryParams(queryParams map[string]string) *ApiRequest {
	if queryParams == nil {
		return r
	}

	r.queryParams = queryParams
	return r
}

// SetPathParams adds the provided path parameters to the ApiRequest
func (r *ApiRequest) SetPathParams(pathParams map[string]string) *ApiRequest {
	if pathParams == nil {
		return r
	}

	r.pathParams = pathParams
	return r
}

// SetPayload adds the provided payload to the ApiRequest
func (r *ApiRequest) SetPayload(payload interface{}) *ApiRequest {
	if r.method != GET && payload != nil {
		r.body = payload
	}

	return r
}

func (method HTTPMethod) String() string {
	switch method {
	case GET:
		return "GET"
	case POST:
		return "POST"
	case PUT:
		return "PUT"
	case PATCH:
		return "PATCH"
	case DELETE:
		return "DELETE"
	}
	return "Unknown Http method"
}
