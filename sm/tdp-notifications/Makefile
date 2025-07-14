include env.mk

git-init-sm:
	@echo "initializing submodules..."
	@git submodule update --init --recursive
	@git submodule update --remote --merge
	@git submodule sync

git-init-hooks:
	@bash githooks/install-hooks.bash

up: down git-init-sm
	@echo starting all services
	$(DOCKER_COMPOSE) -f build/docker-compose.yml up --build $(services); \
	rc=$$? ; \
	$(MAKE) down; \
    exit $$rc

down:
	@echo stopping all services
	$(DOCKER_COMPOSE) -f build/docker-compose.yml -v down

check-code-format:
	 @output=$$(gofmt -s -l $$(find . -type f -name '*.go'| grep -v "/database/")); \
	 if [ -z "$$output" ]; then \
		 echo "Everything is OK. No formatting needed."; \
	 else \
		 echo "Formatting is needed in the following files:"; \
		 echo "$$output"; \
		 exit 1; \
	 fi
