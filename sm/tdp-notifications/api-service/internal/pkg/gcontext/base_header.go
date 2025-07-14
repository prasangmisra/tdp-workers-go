package gcontext

import "github.com/gin-gonic/gin"

const baseHeaderKey = "BaseHeader"

// BaseHeader contains the common header
type BaseHeader struct {
	XTenantCustomerID string `header:"x-tenant-customer-id" binding:"required"`
}

func (h *BaseHeader) SetToGinCtx(c *gin.Context) {
	c.Set(baseHeaderKey, h)
}

func GetBaseHeader(c *gin.Context) (bh *BaseHeader) {
	if h, exists := c.Get(baseHeaderKey); exists {
		bh, _ = h.(*BaseHeader)
	}
	return
}
