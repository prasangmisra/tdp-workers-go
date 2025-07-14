DBNAME=subtdpdb
DBUSER=tucows
DBPASS=tucows1234
DBHOST=localhost
DBPORT=5432
PSQL=PGOPTIONS='--client-min-messages=warning' psql -X -q --single-transaction
CREATEDB=createdb
ECHO=$(shell which echo || /bin/echo)
DOCKER_COMPOSE=docker compose
PLATFORM=$(shell uname -s)

ifeq ("x$(PLATFORM)","xLinux")
DOCKER_COMPOSE="docker-compose"
endif

ifneq ($(DBPASS),)
	PSQL:=PGPASSWORD=$(DBPASS) $(PSQL)
	CREATEDB:=PGPASSWORD=$(DBPASS) $(CREATEDB)
	DROPDB:=PGPASSWORD=$(DBPASS) $(DROPDB)
	DOC:=$(DOC) --password="$(DBPASS)"
endif

export PSQL DBUSER DBHOST DBPORT DBNAME

MODULES = template

.PHONY: $(MODULES)

all: createdb \
	 $(MODULES) \
	 complete \
	 populate_migrations

$(MODULES): modules-prep
	@$(ECHO) -n "    - provisioning $@ ... "
	@$(MAKE) -C $@
	@echo ✅

modules-prep:
	@$(ECHO) "Setting up modules ..."

createdb:
	@$(ECHO) -n "Creating DB ..."
	@$(CREATEDB) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -E UTF8
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -c "ALTER DATABASE $(DBNAME) SET timezone TO 'UTC'"
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f extensions.ddl
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f domains.ddl $(DBNAME)
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f functions.ddl $(DBNAME)
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f common-schema.ddl $(DBNAME)
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f schema.ddl $(DBNAME)
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f init.sql $(DBNAME)
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f views.ddl $(DBNAME)
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f stored-procedures.ddl $(DBNAME)
	

complete:
	@$(ECHO) -n "Completing ..."
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f post-views.ddl
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f triggers.ddl $(DBNAME)
	@echo ✅

test-data:
	-$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f test-data.sql

test:
	$(DOCKER_COMPOSE) -f ../docker-compose.yml -p "${DC_PROJECT_NAME}" exec \
		-e PGUSER='$(DBUSER)' \
		-e PGHOST='localhost' \
		-e PGPORT='5432' \
		-e PGDATABASE='$(DBNAME)' \
		-e PGPASSWORD=$(DBPASS) \
		-w /tests/db sample-db pg_prove -f --recurse t

migrate:
	$(eval VERSION=$(word 2, $(MAKECMDGOALS)))  # Get the first argument as VERSION
	$(eval DESCRIPTION="Migration for version $(VERSION)")  # Set DESCRIPTION based on VERSION

	@$(ECHO) -n "Apply migration files ..."
	PSQL="psql -X -q --single-transaction" PGHOST=$(DBHOST) PGDATABASE=$(DBNAME) PGPORT=$(DBPORT) PGUSER=$(DBUSER) PGPASSWORD=$(DBPASS) ../script/run-migrations $(DBNAME) $(VERSION) $(DESCRIPTION)
	@echo ✅

populate_migrations:
	@$(ECHO) -n "Populate migration files ..."
	PSQL="psql -X -q --single-transaction" PGHOST=$(DBHOST) PGDATABASE=$(DBNAME) PGPORT=$(DBPORT) PGUSER=$(DBUSER) PGPASSWORD=$(DBPASS) ../script/populate-migrations $(DBNAME)
	@echo ✅
