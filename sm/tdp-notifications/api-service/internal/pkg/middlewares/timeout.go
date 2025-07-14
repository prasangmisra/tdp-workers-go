package middlewares

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/lpar/problem"
)

const DefaultTimeoutInSec = 30
const MinTimeoutInSec = 3

// TimeOut processes the x-timeout header and creates a cancellable
// context with timeout that is set with the 'syncTimeoutContext' key in the
// request http context
func TimeOut() gin.HandlerFunc {
	return func(ctx *gin.Context) {
		// wrap original writer such that we can write timeout response
		// regardless if headers were already written down the path
		writer := &timeoutWriter{ResponseWriter: ctx.Writer, h: make(http.Header)}
		ctx.Writer = writer

		// restore context writer once done
		//defer func() { ctx.Writer = writer.ResponseWriter }()

		headerValue := ctx.GetHeader("x-timeout")
		timeout, err := strconv.Atoi(headerValue)
		if err != nil {
			timeout = DefaultTimeoutInSec
		} else if timeout < MinTimeoutInSec {
			writer.ResponseWriter.Header().Set("Content-Type", "application/json")
			response := problem.New(http.StatusBadRequest).WithDetail(fmt.Sprintf("x-timeout must be %v or greater.", MinTimeoutInSec))
			response.Type = "https://datatracker.ietf.org/doc/html/rfc7231#section-6.5.1"
			problem.MustWrite(writer.ResponseWriter, response)
			ctx.Abort()
			return
		}

		timeoutContext, cancel := context.WithTimeout(ctx.Request.Context(), time.Duration(timeout)*time.Second)
		defer cancel()

		completedChan := make(chan struct{})

		go func() {
			// create child context to avoid race condition on Done channels reading
			c, cancel := context.WithCancel(timeoutContext)
			defer cancel()

			ctx.Request = ctx.Request.WithContext(c)

			ctx.Next()

			completedChan <- struct{}{}
		}()

		select {
		case <-completedChan: // When the handler or pipeline middlewares processing finishes without panic
			// if finished, set headers and write resp
			writer.mu.Lock()
			defer writer.mu.Unlock()

			// map Headers from writer.Header() (written to by gin)
			// to writer.ResponseWriter for response
			dst := writer.ResponseWriter.Header()
			for k, vv := range writer.Header() {
				dst[k] = vv
			}
			writer.ResponseWriter.WriteHeader(writer.code)

			// writer.wbuf will have been written to already when gin writes to writer.Write()
			writer.ResponseWriter.Write(writer.wbuf.Bytes())

		case <-timeoutContext.Done(): // When the context times out
			// timeout has occurred, send errTimeout and write headers
			writer.mu.Lock()
			defer writer.mu.Unlock()

			writer.ResponseWriter.Header().Set("Content-Type", "application/json")

			response := problem.New(http.StatusRequestTimeout).WithDetail("timeout")
			response.Type = "https://tools.ietf.org/html/rfc7231#section-6.5.7"
			problem.MustWrite(writer.ResponseWriter, response)

			ctx.Abort()
			writer.SetTimedOut()
		}
	}
}

// implements http.Writer, but tracks if Writer has timed out
// or has already written its header to prevent
// header and body overwrites
// also locks access to this writer to prevent race conditions
// holds the gin.ResponseWriter which we'll manually call Write()
// on in the middleware function to send response
type timeoutWriter struct {
	gin.ResponseWriter
	h    http.Header
	wbuf bytes.Buffer // The zero value for Buffer is an empty buffer ready to use.

	mu          sync.Mutex
	timedOut    bool
	wroteHeader bool
	code        int
}

// Writes the response, but first makes sure there
// hasn't already been a timeout
// In http.ResponseWriter interface
func (writer *timeoutWriter) Write(b []byte) (int, error) {
	writer.mu.Lock()
	defer writer.mu.Unlock()
	if writer.timedOut {
		return 0, nil
	}

	return writer.wbuf.Write(b)
}

// func (writer *timeoutWriter) WriteString(s string) (n int, err error) {
// 	writer.WriteHeaderNow()
// 	n, err = io.WriteString(writer, s)
// 	return
// }

// In http.ResponseWriter interface
func (writer *timeoutWriter) WriteHeader(code int) {
	checkWriteHeaderCode(code)
	writer.mu.Lock()
	defer writer.mu.Unlock()
	// We do not write the header if we've timed out or written the header
	if writer.timedOut || writer.wroteHeader {
		return
	}
	writer.writeHeader(code)
}

func (writer *timeoutWriter) WriteHeaderNow() {
	// We do not write the header if we've timed out or written the header
	if writer.timedOut || writer.wroteHeader {
		return
	}

	writer.ResponseWriter.WriteHeaderNow()
}

// set that the header has been written
func (writer *timeoutWriter) writeHeader(code int) {
	writer.wroteHeader = true
	writer.code = code
}

// Header "relays" the header, h, set in struct
// In http.ResponseWriter interface
func (writer *timeoutWriter) Header() http.Header {
	return writer.h
}

// SetTimeOut sets timedOut field to true
func (writer *timeoutWriter) SetTimedOut() {
	writer.timedOut = true
}

func checkWriteHeaderCode(code int) {
	if code < 100 || code > 999 {
		panic(fmt.Sprintf("invalid WriteHeader code %v", code))
	}
}
