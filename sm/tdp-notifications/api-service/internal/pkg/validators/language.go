package validators

import (
	"github.com/go-playground/validator/v10"
	"strings"
)

// list of languages based on inserted values in db
// https://github.com/tucowsinc/tdp-database-design/blob/81138d6792e4f8c41331ae6b5f4f403d99c0334a/db/init.sql#L257
var languages = map[string]bool{"en": true, "de": true}

func validateLanguage(fl validator.FieldLevel) bool {
	if s, ok := fl.Field().Interface().(string); ok {
		return languages[strings.ToLower(s)]
	}
	return false
}
