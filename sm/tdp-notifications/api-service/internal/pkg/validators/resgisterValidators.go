package validators

import (
	"fmt"

	"github.com/gin-gonic/gin/binding"
	"github.com/go-playground/validator/v10"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/config"
)

const (
	NonBlankTag       = "nonBlank"
	LanguageCodeTag   = "language_code"
	CountryTag        = "country"
	StrongPasswordTag = "strong_password"
	UUIDorFqdnTag     = "is_uuid_or_fqdn"
	HTTPSURLTag       = "https_url"
	URLReachableTag   = "url_reachable"
)

type customValidator struct {
	tag      string
	function validator.Func
}

func RegisterValidators(cfg *config.Config) (err error) {
	v, ok := binding.Validator.Engine().(*validator.Validate)
	if !ok {
		return fmt.Errorf("failed to retrieve validator engine")
	}

	var validators = []customValidator{
		{tag: NonBlankTag, function: nonBlank},
		{tag: LanguageCodeTag, function: validateLanguage},
		{tag: CountryTag, function: validateCountry},
		{tag: StrongPasswordTag, function: validatePassword},
		{tag: UUIDorFqdnTag, function: uuidOrFqdn},
		{tag: HTTPSURLTag, function: urlValidator(cfg)},
		{tag: URLReachableTag, function: urlReachable(cfg)},
	}

	for _, cv := range validators {
		if err := v.RegisterValidation(cv.tag, cv.function); err != nil {
			return fmt.Errorf("failed to register validator for tag '%s': %w", cv.tag, err)
		}
	}

	return nil
}
