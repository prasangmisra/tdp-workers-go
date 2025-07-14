all:
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f stored_procedures.ddl $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f schema.ddl $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f init.sql $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f functions.ddl $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f views.ddl $(DBNAME)
