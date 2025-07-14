include ../common.mk

.PHONY: swagger
swagger:
	cd cmd; \
	swag init --output ../api --dir ./,../internal/app/handlers/rest,../internal/pkg/handlers --parseDependency; \
	cd -

