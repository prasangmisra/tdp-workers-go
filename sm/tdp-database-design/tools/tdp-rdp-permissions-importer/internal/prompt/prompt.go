package prompt

import (
	"errors"
	"github.com/manifoldco/promptui"
	"strings"
)

var templates = &promptui.PromptTemplates{
	Prompt:  "{{ . }} ",
	Valid:   "{{ . | green }} ",
	Invalid: "{{ . | red }} ",
	Success: "{{ . | bold }} ",
}

func Run(name string, optFns ...OptionsFunc) (string, error) {
	opts := apply(optFns...)

	validate := func(input string) error {
		if strings.TrimSpace(input) == "" {
			return errors.New(name + " cannot be empty")
		}
		return nil
	}

	prompt := promptui.Prompt{
		Label:       "Enter " + name,
		Templates:   templates,
		Validate:    validate,
		HideEntered: opts.HideEntered,
	}

	return prompt.Run()
}
