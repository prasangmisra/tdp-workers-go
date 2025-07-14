package template

import (
	"bytes"
	"fmt"
	"html/template"
)

// Given a string template and a map of variables, render the template and return it
func RenderTemplate(emailTemplate string, templateVariables map[string]any) (string, error) {

	// This code was taken from the original email-template-processor service
	tmpl, err := template.New("email").Parse(emailTemplate)
	if err != nil {
		return "", fmt.Errorf("failed to parse template: %w", err)
	}

	var rendered bytes.Buffer
	if err := tmpl.Execute(&rendered, templateVariables); err != nil {
		return "", fmt.Errorf("execute template failed : %w", err)
	}

	return rendered.String(), nil
}
