package config

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestGetEnvironment(t *testing.T) {
	tests := []struct {
		key   string
		value Environment
	}{
		{
			key:   "",
			value: Dev,
		},
		{
			key:   Dev.String(),
			value: Dev,
		},
		{
			key:   Prod.String(),
			value: Prod,
		},
	}
	for _, test := range tests {
		os.Setenv("ENV", test.key)
		env := GetEnvironment()
		assert.Equal(t, test.value, env)
	}
}
