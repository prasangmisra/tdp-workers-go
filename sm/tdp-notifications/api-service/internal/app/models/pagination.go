package models

import (
	"math"

	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/converters"
)

type PagedViewModel struct {
	PageNumber      int  `json:"page_number"`
	PageSize        int  `json:"page_size"`
	TotalCount      int  `json:"total_count"`
	TotalPages      int  `json:"total_pages"`
	HasNextPage     bool `json:"has_next_page"`
	HasPreviousPage bool `json:"has_previous_page"`
}

// Pagination contains the fields to handle paged requests
type Pagination struct {
	PageSize      int    `form:"page_size,default=10" default:"10" binding:"gte=1"`
	PageNumber    int    `form:"page_number,default=1" default:"1" binding:"gte=1"`
	SortBy        string `form:"sort_by,default=created_date" default:"created_date"`
	SortDirection string `form:"sort_direction,default=asc" default:"asc" binding:"oneof=asc desc"`
}

// ToProto converts a Pagination struct to a protobuf PaginationRequest message.
func (p *Pagination) ToProto() *common.PaginationRequest {
	return converters.ConvertOrNil(p, func(p *Pagination) common.PaginationRequest {
		return common.PaginationRequest{
			PageSize:      int32(p.PageSize),
			PageNumber:    int32(p.PageNumber),
			SortBy:        p.SortBy,
			SortDirection: p.SortDirection,
		}
	})
}

// GetPageNumber returns the page number or 0 if Pagination is nil
func (p *Pagination) GetPageNumber() int {
	if p == nil {
		return 0
	}
	return p.PageNumber
}

// GetPageSize returns the page size or 0 if Pagination is nil
func (p *Pagination) GetPageSize() int {
	if p == nil {
		return 0
	}
	return p.PageSize
}

// GetTotalPages returns the total number of pages based on the total count of records or 0 if Pagination is nil
func (p *Pagination) GetTotalPages(totalCount int) int {
	if p == nil {
		return 0
	}
	totalPages := float64(totalCount) / float64(p.GetPageSize())
	return int(math.Ceil(totalPages))
}

// HasNextPage returns false if Pagination is nil, otherwise checks if there are more results
func (p *Pagination) HasNextPage(totalCount int) bool {
	if p == nil {
		return false
	}
	return p.GetPageNumber() < p.GetTotalPages(totalCount)
}

// HasPreviousPage returns false if Pagination is nil, otherwise checks if the current page is greater than 1
func (p *Pagination) HasPreviousPage() bool {
	if p == nil {
		return false
	}
	return p.GetPageNumber() > 1
}
