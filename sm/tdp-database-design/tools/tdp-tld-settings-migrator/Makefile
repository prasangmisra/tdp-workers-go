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
	docker compose -f ./build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" -v down

define run_test
    $(MAKE) test-down
    PRIVATE_MODULES=$(1) docker compose -f ./build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" up --build --abort-on-container-exit --exit-code-from test; \
    rc=$$? ; \
    $(MAKE) test-down; \
    exit $$rc
endef

PRIVATE_MODULES="github.com/tucowsinc/tdp-shared-go/logger github.com/tucowsinc/tdp-shared-go/repository/v3"
.PHONY: itest
itest:
	$(call run_test,${PRIVATE_MODULES})
