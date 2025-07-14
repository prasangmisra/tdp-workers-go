DOCKER_COMPOSE=docker compose
PLATFORM=$(shell uname -s)

ifeq ("x$(PLATFORM)","xLinux")
DOCKER_COMPOSE="docker-compose"
endif

.PHONY = all stop test

all:
	$(DOCKER_COMPOSE) up --build -d
	cd db && sleep 5 && $(MAKE) all test-data

stop:
	$(DOCKER_COMPOSE) down
	-rm .test-data

.test-data:
	cd db && $(MAKE) test-data
	touch .test-data

test: .test-data
	cd db && $(MAKE) test

.PHONY: itest
itest:
	make test-down
	$(DOCKER_COMPOSE) -f docker-compose.yml -p "${DC_PROJECT_NAME}" up --build --detach --wait --wait-timeout 30
	make --directory=db test; \
    rc=$$? ; \
    make test-down; \
    exit $$rc

.PHONY: test-down
test-down:
	@echo stopping test env
	$(DOCKER_COMPOSE) -f docker-compose.yml -p "${DC_PROJECT_NAME}" -v down
