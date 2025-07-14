package validators

import (
	"github.com/go-playground/validator/v10"
	"strings"
)

func isNonBlank(s string) bool {
	s = strings.TrimSpace(s)
	return s != ""
}

// nonBlank is currently just making sure we don't have " " strings
var nonBlank validator.Func = func(fl validator.FieldLevel) bool {
	s, ok := fl.Field().Interface().(string)
	if ok {
		return isNonBlank(s)
	}
	return false
}
