DBNAME=tdpdb
DBUSER=tucows
DBPASS=tucows1234
DBHOST=localhost
DBPORT=5432
DBENV=qa
DOC=postgresql_autodoc
DOC_TARGET=doc
PSQL=PGOPTIONS='--client-min-messages=warning' psql -X -q --single-transaction
CREATEDB=createdb
DROPDB=dropdb
DOT=dot
DBICDUMP=carton exec dbicdump
ECHO=$(shell which echo || /bin/echo)
DOCKER_COMPOSE=docker compose
PLATFORM=$(shell uname -s)

VERSION ?=

ifeq ("x$(PLATFORM)","xLinux")
DOCKER_COMPOSE="docker-compose"
endif

# where to write the go model
MODEL_TARGET=../orm/go/domainsdb


ifneq ($(DBPASS),)
	PSQL:=PGPASSWORD=$(DBPASS) $(PSQL)
	CREATEDB:=PGPASSWORD=$(DBPASS) $(CREATEDB)
	DROPDB:=PGPASSWORD=$(DBPASS) $(DROPDB)
	DOC:=$(DOC) --password="$(DBPASS)"
endif

export PSQL DBUSER DBHOST DBPORT DBNAME DBENV

MODULES = external \
		  customer \
		  jobmanager \
		  backend_provider \
		  event \
		  lock \
		  contact \
		  host \
		  domain \
		  hosting \
		  order \
		  provisioning \
		  tld_config \
		  poll_message \
		  validations \
		  rdp \
		  history \
		  itdp \
		  dm_enom \
		  event \
		  finance_setting \
		  cost \
		  price 

.PHONY: $(MODULES)

all: createdb \
	 provision \
	 $(MODULES) \
	 complete \
	 populate_migrations
	@echo Finished 🏆

$(MODULES): modules-prep
	@$(ECHO) -n "    - provisioning $@ ... "
	@$(MAKE) -C $@
	@echo ✅

modules-prep:
	@$(ECHO) "Setting up modules ..."

createdb:
	@$(ECHO) -n "Creating DB ..."
	@$(CREATEDB) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -E UTF8
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -c "ALTER DATABASE $(DBNAME) SET timezone TO 'UTC'" $(DBNAME)
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f extensions.ddl
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f domains.ddl
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f functions.ddl
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f stored-procedures.ddl
	@echo ✅

error_handling:
	@cd error-handling && $(MAKE)

provision: error_handling
	@$(ECHO) -n "Provisioning ..."
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f schema.ddl
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f views.ddl
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f roles.ddl
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f init.sql
	@echo ✅

complete:
	@$(ECHO) -n "Completing ..."
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f triggers.ddl
	@$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f post-create.sql
	@echo ✅

deltas:
	PSQL="$(PSQL)" PGHOST=$(DBHOST) PGDATABASE=$(DBNAME) PGPORT=$(DBPORT) PGUSER=$(DBUSER) ../script/seed-migrations $(DBNAME)

dropdb:
	-$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f drop-roles.ddl
	-$(DROPDB) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME)

test:
	$(DOCKER_COMPOSE) -f ../docker-compose.yml exec \
		-e PGUSER='$(DBUSER)' \
		-e PGHOST='localhost' \
		-e PGPORT='5432' \
		-e PGDATABASE='$(DBNAME)' \
		-e PGPASSWORD=$(DBPASS) \
		-w /tests/db sample-db pg_prove -f --recurse t

test-finance:
	$(DOCKER_COMPOSE) -f ../docker-compose.yml exec \
		-e PGUSER='$(DBUSER)' \
		-e PGHOST='localhost' \
		-e PGPORT='5432' \
		-e PGDATABASE='$(DBNAME)' \
		-e PGPASSWORD=$(DBPASS) \
		-w /tests/db sample-db pg_prove -f --recurse t_finance 

test-data:
	-$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f test-data.sql

test-finance-data:
	-$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f test-data-cost.sql 
	-$(PSQL) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) $(DBNAME) -f test-data-price.sql
	@echo "Test data loaded ✅"

clean:
	-cd $(DOC_TARGET) && rm -rf *

doc/%:
	$(eval module = $(subst doc/,,$@))
	$(eval pattern = $(shell ./script/tables-in-module $(module)))
	/bin/echo -n "Generating documentation for module: $(module) ... "
	mkdir -p doc/$(module)
	cd doc/$(module) \
		&&      $(DOC) -m '$(pattern)' -f $(module) -h $(DBHOST) -p $(DBPORT) -d $(DBNAME) -u $(DBUSER) >/dev/null 2>&1 \
		&& dot -Tpng $(module).dot -o  $(module).png >/dev/null 2>&1
		echo "done"

doc: clean $(addprefix doc/,$(MODULES))
	@echo Generating documentation for base
	@cd doc && $(DOC) -h $(DBHOST) -p $(DBPORT)  -d $(DBNAME) -u $(DBUSER) >/dev/null 2>&1

er-diagram/order/%:
	$(eval sub_module_file = $(subst er-diagram/order/,,$@))
	$(eval sub_module = $(subst .ddl,,$(sub_module_file)))
	$(eval include_tables = $(shell ./script/tables-in-files-abs order/$(sub_module_file)))
	@mkdir -p er-diagram 
	@if [ "x$(include_tables)" != "x" ] ; then echo "working on order_$(sub_module)" ; cd er-diagram && mermerd -c postgres://$(DBUSER):$(DBPASS)@$(DBHOST):$(DBPORT)/$(DBNAME) -s public $(include_tables) --showAllConstraints -o order_$(sub_module).mmd ; fi

er-diagram/order: $(addprefix er-diagram/,$(shell ls order/*_contact.ddl order/*_domain.ddl))
	$(eval module = $(subst er-diagram/,,$@))
	$(eval include_tables = $(shell ./script/tables-in-files-abs order/schema.ddl))
	@mkdir -p er-diagram 
	@if [ "x$(include_tables)" != "x" ] ; then echo "working on $(module)" ; cd er-diagram && mermerd -c postgres://$(DBUSER):$(DBPASS)@$(DBHOST):$(DBPORT)/$(DBNAME) -s public $(include_tables) --showAllConstraints -o $(module).mmd ; fi

er-diagram/%:
	$(eval module = $(subst er-diagram/,,$@))
#	$(eval include_tables = $(shell ./script/tables-in-module-abs $(module)))
	$(eval include_tables = $(shell ./script/tables-in-files-abs $(module)/*.ddl))
	@mkdir -p er-diagram 
	@if [ "x$(include_tables)" != "x" ] ; then echo "working on $(module)" ; cd er-diagram && mermerd -c postgres://$(DBUSER):$(DBPASS)@$(DBHOST):$(DBPORT)/$(DBNAME) -s public $(include_tables) --showAllConstraints -o $(module).mmd ; fi

er-diagram: $(addprefix er-diagram/,$(MODULES))
	@echo Generating documentation for base
	@cd er-diagram && mermerd -c postgres://$(DBUSER):$(DBPASS)@$(DBHOST):$(DBPORT)/$(DBNAME) -s public --useAllTables -o diagram.mmd
	@sed -i -e 's/ _/ /' er-diagram/diagram.mmd
	@echo 📖 ✅ 

perl_model:
	@$(ECHO) -n "Generating Perl 5 🐪 library ..."
	@PERL5LIB=$(PERL5LIB) \
	PATH=../local/bin:$(PATH) \
	DBHOST=$(DBHOST) \
	DBPORT=$(DBPORT) \
	DBUSER=$(DBUSER) \
	DBPASS=$(DBPASS) \
	DBNAME=$(DBNAME) \
	$(DBICDUMP) dbicdump-conf.pl 2>perl_model.log 1>&2
	@echo ✅

perl_deps:
	@$(ECHO) -n "installing 🐪 dependencies (see perl_deps.log)..."
	@carton 2>&1 1>perl_deps.log
	@echo ✅


go_model:
	@$(ECHO) -n "Generating Go model 👽"
	@mkdir -p $(MODEL_TARGET)
	@carton exec ./script/schemadump --dbhost $(DBHOST) \
	                    --dbname $(DBNAME) \
	                    --dbport $(DBPORT) \
	                    --dbuser $(DBUSER) \
						--dbpass $(DBPASS) \
	                    --skip-pattern "_\d+$$" \
						--skip-rel pg_all_foreign_keys \
						--skip-rel tap_funky \
	                    --target-dir $(MODEL_TARGET)
	@cd $(MODEL_TARGET) && go fmt *go >/dev/null
	@echo ✅

models: perl_deps perl_model go_model
	@echo "🏆 completed generating models"

migrate:
	PSQL="psql -X -q --single-transaction" PGHOST=$(DBHOST) PGDATABASE=$(DBNAME) PGPORT=$(DBPORT) PGUSER=$(DBUSER) PGPASSWORD=$(DBPASS) ../script/run-migrations $(DBNAME) $(VERSION)
	@echo ✅

populate_migrations:
	@$(ECHO) -n "Populate migration files ..."
	PSQL="psql -X -q --single-transaction" PGHOST=$(DBHOST) PGDATABASE=$(DBNAME) PGPORT=$(DBPORT) PGUSER=$(DBUSER) PGPASSWORD=$(DBPASS) ../script/populate-migrations $(DBNAME)
	@echo ✅
