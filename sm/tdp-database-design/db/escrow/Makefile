
all:
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f schema.ddl $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f enom/schema.ddl $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f opensrs/schema.ddl $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f functions.ddl $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f triggers.ddl $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f init.sql $(DBNAME)
