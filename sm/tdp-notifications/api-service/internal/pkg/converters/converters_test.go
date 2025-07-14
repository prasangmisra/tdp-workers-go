package converters

import (
	"testing"

	"github.com/google/uuid"
	"github.com/samber/lo"
	"github.com/stretchr/testify/require"
)

func TestMap(t *testing.T) {
	t.Parallel()
	type A string
	type B int32
	const (
		a1 A = "a1"
		a2 A = "a2"
		a3 A = "a3"
		a4 A = "a4"
		a5 A = "a5"
	)
	const (
		b1 B = iota
		b2
		b3
		b4
	)
	abMap := map[A]B{
		a1: b1,
		a2: b2,
		a3: b3,
		a4: b4,
	}

	tests := []struct {
		name     string
		aSlice   []A
		expected []B
	}{
		{
			name: "nil slice",
		},
		{
			name:     "non-existing element in map - should map to default value b1",
			aSlice:   []A{a5},
			expected: []B{b1},
		},
		{
			name:     "only existing elements, don't repeat",
			aSlice:   []A{a1, a2, a3, a4},
			expected: []B{b1, b2, b3, b4},
		},
		{
			name:     "mixed slice",
			aSlice:   []A{a3, a1, a3, a2, a5},
			expected: []B{b3, b1, b3, b2, b1},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			require.Equal(t, tc.expected, Map(tc.aSlice, abMap))
		})
	}
}

func TestConvertOrNil(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		id       *uuid.UUID
		expected *string
	}{
		{
			name: "nil uuid",
		},
		{
			name:     "zero uuid",
			id:       &uuid.UUID{},
			expected: lo.ToPtr("00000000-0000-0000-0000-000000000000"),
		},
		{
			name:     "non-zero uuid",
			id:       lo.ToPtr(uuid.MustParse("1cb6002d-eea0-48b3-87f0-7285536956c9")),
			expected: lo.ToPtr("1cb6002d-eea0-48b3-87f0-7285536956c9"),
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			require.Equal(t, tc.expected, ConvertOrNil(tc.id, func(id *uuid.UUID) string {
				return id.String()
			}))
		})
	}
}

func TestStringToPtr(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		input    string
		expected *string
	}{
		{
			name:     "empty string",
			input:    "",
			expected: nil,
		},
		{
			name:     "non empty",
			input:    "some description",
			expected: lo.ToPtr("some description"),
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			require.Equal(t, tc.expected, StringToPtr(tc.input))
		})
	}
}
