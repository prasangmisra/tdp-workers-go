package validators

import (
	"net/url"

	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/config"

	"github.com/go-playground/validator/v10"
)

const (
	HTTPS = "https"
)

// isValidHTTPSURL checks if the provided string is a valid HTTPS URL and reachable using a HEAD request.
func isValidHTTPSURL(rawURL string) bool {
	parsedURL, err := url.Parse(rawURL)
	if err != nil {
		return false
	}

	return parsedURL.Scheme == HTTPS

}

// urlValidator checks whether the input string is a valid, reachable HTTPS URL
func urlValidator(cfg *config.Config) validator.Func {
	return func(fl validator.FieldLevel) bool {
		if !cfg.Validator.HttpsUrl {
			return true
		}
		url, ok := fl.Field().Interface().(string)
		if ok {
			return isValidHTTPSURL(url)
		}
		return false
	}

}
