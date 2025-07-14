package messaging

import (
	"github.com/gin-gonic/gin"
	"github.com/tucowsinc/tdp-notifications/api-service/internal/pkg/gcontext"
	"strconv"
	"time"
)

// DeadlineResponseTimeoutPerc a fraction (%) of timeout reserved to insure
// data manager on deadline response is received before request times out
const DeadlineResponseTimeoutPerc = 10

// GetHeaders gets headers to pass to message bus from request
func GetHeaders(ctx *gin.Context) (headers map[string]any) {
	headers = make(map[string]any)

	t := ctx.GetHeader("x-try-sync")
	trySync, err := strconv.ParseBool(t)
	if err != nil {
		trySync = false
	}

	headers["try-sync"] = trySync
	headers["traceparent"] = ctx.GetHeader("traceparent")
	headers["tracestate"] = ctx.GetHeader("tracestate")

	// deadline is used for sync requests only
	//
	if deadline, ok := ctx.Request.Context().Deadline(); ok && trySync {
		headers["deadline"] = deadline.UnixNano() - DeadlineResponseTimeoutPerc*(deadline.UnixNano()-time.Now().UnixNano())/100
	}

	// Retrieve the bound BaseHeader from the context
	if baseHeader := gcontext.GetBaseHeader(ctx); baseHeader != nil {
		headers["tenant-customer-id"] = baseHeader.XTenantCustomerID
	}

	return
}
