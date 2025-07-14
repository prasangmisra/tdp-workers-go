package validators

import (
	"github.com/go-playground/validator/v10"
	"github.com/google/uuid"
)

func is_uuid_or_fqdn(s string) bool {
	return IsValidFQDN(s) || IsValidUUID(s)
}

// IsValidUUID checks if a string is a valid UUID
func IsValidUUID(s string) bool {
	_, err := uuid.Parse(s)
	return err == nil
}

// Checks if a string is a valid FQDN
func IsValidFQDN(s string) bool {
	v := validator.New()
	err := v.Var(s, "fqdn")
	return err == nil
}

// uuidOrFqdn checks whether the input string is either fqdn or uuid
var uuidOrFqdn validator.Func = func(fl validator.FieldLevel) bool {
	s, ok := fl.Field().Interface().(string)
	if ok {
		return is_uuid_or_fqdn(s)
	}
	return false
}
