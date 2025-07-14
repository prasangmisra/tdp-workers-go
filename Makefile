SHELL = /bin/sh
ENVFILE=./build/generated_env/.secrets

define run_test
    SERVICE_TYPE=$(1) docker-compose -f build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" up --build --abort-on-container-exit --exit-code-from test test; \
    rc=$$? ; \
    docker-compose -f build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" down -v --rmi local ; \
    exit $$rc
endef

define run_test_sub
    SERVICE_TYPE=$(1) docker-compose -f build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" up --build --abort-on-container-exit --exit-code-from test-sub test-sub; \
    rc=$$? ; \
    docker-compose -f build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" down -v --rmi local ; \
    exit $$rc
endef

all: git-init 
	@echo "🏁"

git-init:
	@echo "initializing submodules..."
	@git submodule update --init --recursive
	@git submodule update --remote --merge
	@git submodule sync

init-git-hooks:
	@bash scripts/install-hooks.bash

getenv:
	docker login artifacts.cnco.tucows.systems
	docker-compose -f build/docker-compose-getenv.yml run getenv

get_dd_env:
	docker compose -f ./build/docker-compose-get_dd_env.yml run get_dd_env

up: check-env down
	@echo starting workers
	docker-compose -f build/docker-compose-workers.yml -p "${DC_PROJECT_NAME}" up -d --build domainsdb subdb rabbitmq unbound_resolver
	sleep 10
	docker-compose -f build/docker-compose-workers.yml -p "${DC_PROJECT_NAME}" exec -w /db  -T domainsdb make all test-data
	docker-compose -f build/docker-compose-workers.yml -p "${DC_PROJECT_NAME}" exec -w /subscriptiondb  -T subdb make all test-data
	docker-compose -f ./build/docker-compose-workers.yml -f  ./build/docker-compose-crons.yml up -d --build

down:
	@echo stopping workers
	docker-compose -f ./build/docker-compose-workers.yml -f ./build/docker-compose-crons.yml down -v --rmi local



test-db-up: db-down
	@echo starting db
	docker-compose -f build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" up --build -d domainsdb
	docker-compose -f build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" up --build -d --wait domainsdb
	docker-compose -f build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" exec -w /db  -T domainsdb make all test-data DBENV=dev


test-subdb-up: db-down
	@echo starting db
	docker-compose -f build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" up -d subdb
	sleep 10
	docker-compose -f build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" exec -w /subscriptiondb  -T subdb make all test-data

db-down:
	@echo stopping db
	docker-compose -f ./build/docker-compose-test.yml -p "${DC_PROJECT_NAME}" down -v --rmi local

all-tests: db-down job_scheduler-test contact-test contact_updater-test domain-test domain_updater-test host-test host_updater-test hosting-test hosting_updater-test poll_enqueuer-test poll_worker-test notification_worker-test certificate_updater-test crons-test
	@echo "All workers tests completed."

# Define dependencies for each specific test target
job_scheduler-test: test-db-up
contact-test: test-db-up
contact_updater-test: test-db-up
domain-test: test-db-up
domain_updater-test: test-db-up
host-test: test-db-up
host_updater-test: test-db-up
hosting-test: test-db-up
hosting_updater-test: test-db-up
poll_worker-test: test-db-up
poll_enqueuer-test: test-db-up
notification_worker-test: test-subdb-up
certificate_updater-test: test-db-up
crons-test: test-db-up



# Generic pattern rule for all service tests
# Matches targets like 'job_scheduler-test', 'contact-test', etc.
# The prerequisite (database setup) is handled by the specific target dependencies above.
%-test:
	@echo "Running test for $*"
ifeq ($@,notification_worker-test)
	$(call run_test_sub,$*)
else
	$(call run_test,$*)
endif



check-env:
ifeq ("$(wildcard $(ENVFILE))","")
	$(error make getenv must be run first)
endif

check-code-format:
	 @output=$$(gofmt -s -l $$(find . -type f -name '*.go'| grep -v "/sm/")); \
	 if [ -z "$$output" ]; then \
		 echo "Everything is OK. No formatting needed."; \
	 else \
		 echo "Formatting is needed in the following files:"; \
		 echo "$$output"; \
		 exit 1; \
	 fi

format-code:
	 @output=$$(gofmt -s -w -l $$(find . -type f -name '*.go'| grep -v "/sm/")); \
	 if [ -z "$$output" ]; then \
		 echo "Everything is OK. No formatting needed."; \
	 else \
		 echo "Formatted the following files:"; \
		 echo "$$output"; \
		 exit 0; \
	 fi
