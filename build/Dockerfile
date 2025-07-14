# First stage, generate an image used to build our Go program under a suitable
# runtime.
ARG GOLANG_VERSION=1.19.4

FROM golang:${GOLANG_VERSION} AS builder

LABEL maintainer="Francisco Obispo <fobispo@tucows.com>"

ARG SERVICE_TYPE

WORKDIR /app 

ENV SERVICE_TYPE=${SERVICE_TYPE}

RUN go install github.com/githubnemo/CompileDaemon@v1.4.0

COPY ./go.mod ./go.sum ./

# Install Private GO Packages
RUN GOPROXY="https://artifacts.cnco.tucows.systems/artifactory/api/go/domains-go-virtual" \ 
    go mod download \ 
    github.com/tucowsinc/tdp-messagebus-go \
    github.com/tucowsinc/tdp-messages-go \
    github.com/tucowsinc/tucows-domainshosting-app \
    github.com/tucowsinc/tdp-shared-go/linq \
    github.com/tucowsinc/tdp-shared-go/memoizelib \
    github.com/tucowsinc/tdp-shared-go/dns \
    github.com/tucowsinc/tdp-shared-go/logger \
    github.com/tucowsinc/tdp-shared-go/tracing \
    github.com/tucowsinc/tdp-shared-go/healthcheck
RUN go mod download -x

COPY ${SERVICE_TYPE} ${SERVICE_TYPE}/
COPY pkg ./pkg
COPY .env .
COPY Makefile .

RUN CGO_ENABLED=0 GOOS=linux go build -o /${SERVICE_TYPE} ${SERVICE_TYPE}/cmd/main.go

########## Image for prod env ##########
FROM alpine:latest AS app

ARG SERVICE_TYPE
ENV SERVICE_TYPE=${SERVICE_TYPE}

RUN apk add --no-cache make
COPY Makefile .
COPY .env .

COPY --from=builder /${SERVICE_TYPE} /${SERVICE_TYPE}

CMD /${SERVICE_TYPE}

########## Image for local env ##########
FROM builder AS app-local

COPY build/entrypoint.sh /
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]

########## Image to run unit tests ##########
FROM builder AS app-test

RUN go install github.com/jstemmer/go-junit-report/v2@latest
RUN go install github.com/axw/gocov/gocov@v1.1.0
RUN go install github.com/AlekSi/gocov-xml@latest

COPY build/test-entrypoint.sh /
RUN chmod +x /test-entrypoint.sh

ENTRYPOINT ["/test-entrypoint.sh"]
