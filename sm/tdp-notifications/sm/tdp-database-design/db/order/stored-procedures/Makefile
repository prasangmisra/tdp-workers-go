# Directories
DIRS = helpers validation processing event

# Get all SQL files in the specified directories
FILES = $(foreach dir,$(DIRS),$(wildcard $(dir)/*.ddl))

all:
	@for file in $(FILES); do \
		$(PSQL) $(PSQL_FLAGS) -U $(DBUSER) -h $(DBHOST) -p $(DBPORT) -f $$file $(DBNAME); \
	done
