# RDP Permissions Migrator
This tool migrates RDP (Registration Data Policy) permissions from a CSV file into the `domain_data_element_permission` table of the TDP database.


## File
The provided CSV file should contain the following columns:
1. `Object` - Represents the contact type (eg. Registrant, Admin, Tech, Billing)
2. `Database element name` - Name of the child data element
3. `collection` - Permission name for data collection
4. `transmission (registry)` - Permission name for registry transmission
5. `transmission (escrow)` - Permission name for escrow transmission
6. `publish_by_default` - Permission name for default publication
7. `available_for_consent` - Permission name for availability for consent

## Rules
1. All permission values in the file must exist in the permission table. If any referenced permission does not exist, the process will be terminated.

2. The data element must be resolvable by joining `data_element.name` with its parent’s name (contact type) — both must exist in the data_element table.

3. If the corresponding domain_data_element already exists for a given TLD and data element, it will be reused; otherwise, a new one will be created.

4. If any error occurs during the migration of a record, it will be logged and the process will be terminated.

5. The entire migration runs within a database transaction. If a critical failure occurs before any record is written, no changes will be made to the database.

An example of the file: [example.csv](./example.csv)

## Usage
```bash
go run main.go migrate -f <file> -x <tld> [-s <host>] [-p <port>] [-d <dbname>] [-u <user>] [-w <password>] [flags]
```

### Example of usage
```bash
go run main.go migrate -f example.csv -x exampletld
```

## Flags
```bash
-d, --dbname string   postgres database name (default "tdpdb")
-f, --file string     path to the csv file
-h, --help            help for migrate
-s, --host string     postgres host (default "localhost")
-p, --port int        postgres port (default 5432)
-w, --pass string     postgres password (DO NOT USE flag for PROD credentials, use prompt instead)
-t, --timeout int     postgres database connection timeout in seconds (default 5)
-u, --user string     postgres user (DO NOT USE flag for PROD credentials, use prompt instead)
-x, --tld string      tld to be used in the migration (e.g., "com", "org")
```