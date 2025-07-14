include ../env.mk

.PHONY: gen
gen:
	go generate ./...

.PHONY: fmt
fmt:
	go fmt ./...

.PHONY: tidy
tidy:
	go mod tidy

.PHONY: utest
utest:
	go test -cover ./...

.PHONY: test-down
test-down:
	@echo stopping test env
	$(DOCKER_COMPOSE) -f ./build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" -v down

.PHONY: itest
itest:
	make test-down
	$(DOCKER_COMPOSE) -f ./build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" up --build --abort-on-container-exit --exit-code-from test; \
	rc=$$? ; \
	make test-down; \
	exit $$rc
