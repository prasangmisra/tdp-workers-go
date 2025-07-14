package template

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestRenderTemplate(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name              string
		emailTemplate     string
		templateVariables map[string]any
		expectedOutput    string
		expectError       bool
	}{
		{
			name:          "Valid template with variables",
			emailTemplate: "Hello, {{.Name}}! Welcome to {{.Platform}}.",
			templateVariables: map[string]any{
				"Name":     "John",
				"Platform": "GoLang",
			},
			expectedOutput: "Hello, John! Welcome to GoLang.",
			expectError:    false,
		},
		{
			name:              "Empty template",
			emailTemplate:     "",
			templateVariables: map[string]any{},
			expectedOutput:    "",
			expectError:       false,
		},
		{
			name:          "Invalid template syntax",
			emailTemplate: "Hello, {{.Name! Welcome to {{.Platform}}.",
			templateVariables: map[string]any{
				"Name":     "John",
				"Platform": "GoLang",
			},
			expectedOutput: "",
			expectError:    true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			output, err := RenderTemplate(tc.emailTemplate, tc.templateVariables)
			if tc.expectError {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tc.expectedOutput, output)
			}
		})
	}
}
