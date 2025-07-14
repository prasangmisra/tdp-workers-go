package validators

import (
	"github.com/go-playground/validator/v10"
	"unicode"
)

const (
	minLowercase      = 1
	minUppercase      = 1
	minNumber         = 1
	minSpecial        = 1
	maxPasswordLength = 128
	minPasswordLength = 14
)

func validatePassword(fl validator.FieldLevel) bool {
	password, ok := fl.Field().Interface().(string)
	if !ok {
		return false
	}
	passwordLength := len(password)
	if passwordLength > maxPasswordLength || passwordLength < minPasswordLength {
		return false
	}

	var (
		countLowercase, countUppercase, countNumber, countSpecial int
	)

	for _, char := range password {
		switch {
		case unicode.IsSpace(char):
			return false
		case unicode.IsLower(char):
			countLowercase++
		case unicode.IsUpper(char):
			countUppercase++
		case unicode.IsDigit(char):
			countNumber++
		case unicode.IsPunct(char) || unicode.IsSymbol(char):
			countSpecial++
		}
	}

	// Check if all conditions are satisfied
	return countLowercase >= minLowercase &&
		countUppercase >= minUppercase &&
		countNumber >= minNumber &&
		countSpecial >= minSpecial
}
