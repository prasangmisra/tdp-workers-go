# Start from golang v1.23.0 base image to have access to go modules
ARG GOLANG_VERSION=1.23.0

FROM golang:${GOLANG_VERSION} as builder

LABEL maintainer="Jinish Bhardwaj <jbhardwaj@tucows.com>"

ARG SERVICE_TYPE

WORKDIR /app/${SERVICE_TYPE}

RUN go install github.com/githubnemo/CompileDaemon@latest

COPY ${SERVICE_TYPE}/go.mod ${SERVICE_TYPE}/go.sum ./

# Install Private GO Packages
RUN GOPROXY="https://artifacts.cnco.tucows.systems/artifactory/api/go/domains-go-virtual" \
    go mod download github.com/tucowsinc/...

RUN go mod download -x

COPY ${SERVICE_TYPE} ./
COPY env.mk ../
COPY common.mk ../

RUN CGO_ENABLED=0 GOOS=linux go build -o /${SERVICE_TYPE} cmd/main.go

########## Image for prod env ##########
FROM alpine:latest as app

ARG SERVICE_TYPE
ENV SERVICE_TYPE=${SERVICE_TYPE}

RUN apk add --no-cache make
COPY env.mk .
COPY Makefile .
COPY ${SERVICE_TYPE}/configs configs/
COPY --from=builder /${SERVICE_TYPE} /${SERVICE_TYPE}

CMD /${SERVICE_TYPE}


########## Image for local env ##########
FROM builder as app-local

COPY build/entrypoint.sh /
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]

########## Image to run integration tests ##########
FROM builder as app-test

RUN go install github.com/jstemmer/go-junit-report/v2@latest
RUN go install github.com/axw/gocov/gocov@latest
RUN go install github.com/AlekSi/gocov-xml@latest

COPY build/test-entrypoint.sh /
RUN chmod +x /test-entrypoint.sh

ENTRYPOINT ["/test-entrypoint.sh"]