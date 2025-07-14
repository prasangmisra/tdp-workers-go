package validators

import (
	"net/http"

	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/config"

	"github.com/go-playground/validator/v10"
)

var HttpHeadFunc = http.Head

// isValidHTTPSURL checks if the provided string is a valid HTTPS URL and reachable using a HEAD request.
func isURLReachable(rawURL string) bool {
	resp, err := HttpHeadFunc(rawURL)
	if err != nil {
		return false
	}

	defer resp.Body.Close()

	return resp.StatusCode >= 200 && resp.StatusCode < 300
}

// urlReachable checks whether the HEAD request on the url gives a valid response
func urlReachable(cfg *config.Config) validator.Func {
	return func(fl validator.FieldLevel) bool {
		if !cfg.Validator.UrlReachability {
			return true
		}
		url, ok := fl.Field().Interface().(string)
		if ok {
			return isURLReachable(url)
		}
		return false
	}
}
