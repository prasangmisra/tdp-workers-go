package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type DefaultResponse struct {
	Message string `json:"message"`
} // @name DefaultResponse

// DefaultHandler godoc
// @Summary 		Handles the default route for the api
// @Schemes
// @ Description	Handles the default [/] and returns a message if the api is up and running
// @Tags			general
// @Produces		json
// @Success			200 {object} DefaultResponse
// @Failure			default
// @Router			/ [get]
func DefaultHandler() gin.HandlerFunc {
	return func(ctx *gin.Context) {
		msg := DefaultResponse{Message: "tdp-notifications api running..."}
		ctx.IndentedJSON(http.StatusOK, msg)
	}
}
