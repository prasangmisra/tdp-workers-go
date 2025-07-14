DOCKER_COMPOSE=docker compose
PLATFORM=$(shell uname -s)

ifeq ("x$(PLATFORM)","xLinux")
DOCKER_COMPOSE="docker-compose"
endif

.PHONY = all stop test

all:
	$(DOCKER_COMPOSE) up --build -d
	cd db && sleep 5 && $(MAKE) all test-data DBENV=dev

stop:
	$(DOCKER_COMPOSE) down
	-rm .test-data

.test-data:
	touch .test-data

.finance-data:
	cd db && $(MAKE) test-finance-data
	touch .test-finance-data

test: .test-data
	cd db && $(MAKE) test

test-finance-data: .finance-data
	cd db && $(MAKE) test-finance
