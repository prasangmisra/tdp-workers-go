
all:
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f schema.ddl $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f views.ddl $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f stored-procedures/helpers.ddl $(DBNAME)	
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f stored-procedures/price_calculations.ddl $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f triggers.ddl $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f init.sql $(DBNAME)
#	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f views.ddl $(DBNAME)