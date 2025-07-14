package validators

import "testing"

func TestIsNonBlank(t *testing.T) {
	type test struct {
		name     string
		input    string
		expected bool
	}

	tests := []test{
		{
			name:     "valid string",
			input:    " test ",
			expected: true,
		},
		{
			name:     "spaces",
			input:    "   ",
			expected: false,
		},
		{
			name:     "tab",
			input:    "	",
			expected: false,
		},
	}

	for _, tc := range tests {
		if res := isNonBlank(tc.input); res != tc.expected {
			t.Errorf("%s test failed, expected: %t actual: %t", tc.name, tc.expected, res)
		}
	}
}
