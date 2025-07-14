package converters

import "github.com/samber/lo"

// Map manipulates a slice and transforms it to a slice of another type based on provided mapping
func Map[T comparable, R any](collection []T, mapping map[T]R) []R {
	if collection == nil {
		return nil
	}

	result := make([]R, len(collection))

	for i := range collection {
		result[i] = mapping[collection[i]]
	}

	return result
}

// ConvertOrNil applies converter to the value t if it is not nil or returns nil otherwise
func ConvertOrNil[T any, R any](t *T, converter func(*T) R) *R {
	if t == nil {
		return nil
	}

	return lo.ToPtr(converter(t))
}

// ConvertOrEmpty applies converter to the value t if it is not nil or returns empty value of R type otherwise
func ConvertOrEmpty[T any, R any](t *T, converter func(*T) R) R {
	var zero R
	if t == nil {
		return zero
	}

	return converter(t)
}

func StringToPtr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
