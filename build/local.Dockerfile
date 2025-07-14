# Start from golang v1.19.4 base image to have access to go modules
ARG GOLANG_VERSION=1.19.4

FROM golang:${GOLANG_VERSION} as builder

LABEL maintainer="Francisco Obispo <fobispo@tucows.com>"

ARG SERVICE_TYPE
ARG PROJECT_DIR
ARG GO_PACKAGES_DIR

WORKDIR /app

ENV SERVICE_TYPE=${SERVICE_TYPE}
ENV PROJECT_DIR=${PROJECT_DIR:-"tdp-workers-go"}
ENV GO_PACKAGES_DIR=${GO_PACKAGES_DIR:-"tdp-workers-go"}

RUN go install github.com/githubnemo/CompileDaemon@v1.4.0

COPY ${GO_PACKAGES_DIR}/tdp-messagebus-go ./tdp-messagebus-go
COPY ${GO_PACKAGES_DIR}/tdp-messages-go ./tdp-messages-go
COPY ${GO_PACKAGES_DIR}/tdp-shared-go ./tdp-shared-go

COPY ${PROJECT_DIR}/go.mod ${PROJECT_DIR}/go.sum ./

RUN echo "replace github.com/tucowsinc/tdp-messagebus-go => ./tdp-messagebus-go" >> go.mod
RUN echo "replace github.com/tucowsinc/tdp-messages-go => ./tdp-messages-go" >> go.mod
RUN echo "replace github.com/tucowsinc/tdp-shared-go/linq => ./tdp-shared-go/linq" >> go.mod
RUN echo "replace github.com/tucowsinc/tdp-shared-go/dns => ./tdp-shared-go/dns" >> go.mod
RUN echo "replace github.com/tucowsinc/tdp-shared-go/logger => ./tdp-shared-go/logger" >> go.mod
RUN echo "replace github.com/tucowsinc/tdp-shared-go/tracing => ./tdp-shared-go/tracing" >> go.mod
RUN echo "replace github.com/tucowsinc/tdp-shared-go/memoizelib => ./tdp-shared-go/memoizelib" >> go.mod

# Install Private GO Packages
RUN GOPROXY="https://artifacts.cnco.tucows.systems/artifactory/api/go/domains-go-virtual" \ 
    go mod download \
    github.com/tucowsinc/tucows-domainshosting-app

RUN go mod download -x

COPY ${PROJECT_DIR}/${SERVICE_TYPE} ${SERVICE_TYPE}/
COPY ${PROJECT_DIR}/pkg pkg/
COPY ${PROJECT_DIR}/Makefile .
COPY ${PROJECT_DIR}/.env .

RUN CGO_ENABLED=0 GOOS=linux go build -o /${SERVICE_TYPE} ${SERVICE_TYPE}/cmd/main.go

########## Image for local env ##########
FROM builder as app-local

COPY ${PROJECT_DIR}/build/entrypoint.sh /
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]

########## Image to run unit tests ##########
FROM builder as app-test

RUN go install github.com/jstemmer/go-junit-report/v2@latest
RUN go install github.com/axw/gocov/gocov@v1.1.0
RUN go install github.com/AlekSi/gocov-xml@latest

COPY ${PROJECT_DIR}/build/test-entrypoint.sh /
RUN chmod +x /test-entrypoint.sh

CMD ["/test-entrypoint.sh"]
