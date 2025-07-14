package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/tucowsinc/tdp-messages-go/message/common"
)

func TestPagination_GetPageNumber(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		pagination *Pagination
		expected   int
	}{
		{
			name:       "Valid pagination",
			pagination: &Pagination{PageNumber: 2},
			expected:   2,
		},
		{
			name:       "Nil pagination",
			pagination: nil,
			expected:   0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			assert.Equal(t, tt.expected, tt.pagination.GetPageNumber())
		})
	}
}

func TestPagination_GetPageSize(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		pagination *Pagination
		expected   int
	}{
		{
			name: "Valid pagination",
			pagination: &Pagination{
				PageSize: 20,
			},
			expected: 20,
		},
		{
			name:       "Nil pagination",
			pagination: nil,
			expected:   0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			assert.Equal(t, tt.expected, tt.pagination.GetPageSize())
		})
	}
}

func TestPagination_GetTotalPages(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name         string
		pagination   *Pagination
		totalCount   int
		expectedPage int
	}{
		{
			name:         "Total pages exact match",
			pagination:   &Pagination{PageSize: 10},
			totalCount:   100,
			expectedPage: 10,
		},
		{
			name: "Total pages with remainder",
			pagination: &Pagination{
				PageSize: 10,
			},
			totalCount:   105,
			expectedPage: 11,
		},
		{
			name: "Total pages single page",
			pagination: &Pagination{
				PageSize: 50,
			},
			totalCount:   30,
			expectedPage: 1,
		},
		{
			name: "Total pages with no records",
			pagination: &Pagination{
				PageSize: 10,
			},
			totalCount:   0,
			expectedPage: 0,
		},
		{
			name:         "Nil pagination",
			pagination:   nil,
			totalCount:   100,
			expectedPage: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			totalPages := tt.pagination.GetTotalPages(tt.totalCount)
			assert.Equal(t, tt.expectedPage, totalPages)
		})
	}
}

func TestPagination_HasNextPage(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name            string
		pagination      *Pagination
		totalCount      int
		expectedHasNext bool
	}{
		{
			name: "Has next page",
			pagination: &Pagination{
				PageNumber: 1,
				PageSize:   10,
			},
			totalCount:      30,
			expectedHasNext: true},
		{
			name: "No next page",
			pagination: &Pagination{
				PageNumber: 3,
				PageSize:   10,
			},
			totalCount:      30,
			expectedHasNext: false},
		{
			name: "Single page only",
			pagination: &Pagination{
				PageNumber: 1,
				PageSize:   10,
			},
			totalCount:      5,
			expectedHasNext: false,
		},
		{
			name: "Zero records",
			pagination: &Pagination{
				PageNumber: 1,
				PageSize:   10,
			},
			totalCount:      0,
			expectedHasNext: false,
		},
		{
			name:            "Nil pagination",
			pagination:      nil,
			totalCount:      30,
			expectedHasNext: false, // Nil pagination should return false for HasNextPage
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			hasNext := tt.pagination.HasNextPage(tt.totalCount)
			assert.Equal(t, tt.expectedHasNext, hasNext)
		})
	}
}

func TestPagination_HasPreviousPage(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name                string
		pagination          *Pagination
		expectedHasPrevious bool
	}{
		{
			name: "Has previous page",
			pagination: &Pagination{
				PageNumber: 2,
			},
			expectedHasPrevious: true,
		},
		{
			name: "First page",
			pagination: &Pagination{
				PageNumber: 1,
			},
			expectedHasPrevious: false},
		{
			name:                "Nil pagination",
			pagination:          nil,
			expectedHasPrevious: false, // Nil pagination should return false for HasPreviousPage
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			hasPrevious := tt.pagination.HasPreviousPage()
			assert.Equal(t, tt.expectedHasPrevious, hasPrevious)
		})
	}
}

func TestPagination_ToProto(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		pagination *Pagination
		expected   *common.PaginationRequest
	}{
		{
			name: "Valid pagination",
			pagination: &Pagination{
				PageSize:      10,
				PageNumber:    2,
				SortBy:        "created_date",
				SortDirection: "asc",
			},
			expected: &common.PaginationRequest{
				PageSize:      10,
				PageNumber:    2,
				SortBy:        "created_date",
				SortDirection: "asc",
			},
		},
		{
			name:       "Nil pagination",
			pagination: nil,
			expected:   nil, // Nil pagination should return nil
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			assert.Equal(t, tt.expected, tt.pagination.ToProto())
		})
	}
}
