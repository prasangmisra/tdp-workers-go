
all:
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f schema.ddl $(DBNAME)
	@$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f init.sql $(DBNAME)
