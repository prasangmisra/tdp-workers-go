# TLD Settings Migrator
This script is used to migrate data from a csv file with tld settings provided via flag to database tld_config module.
## File
Provided csv file should use ";" as a separator and should have the following columns: `Tenant Name`, `TLD Name`, `Category Name`, `Setting Name`, `Value to upload`.

1. The `Value to upload` provided in the file should have valid `attr_value_type` for the specified `<category_name>` and `<setting_name?`, 
otherwise the migration will fail and no changes to database state will be made.
2. `Category Name` and `Setting Name` values should have an existing entry in `v_attribute` with the key in the format `tld.<category_name>.<setting_name>`, 
otherwise the corresponding line from the file will be ignored.

An example of the file: [example.csv](./example.csv)

## Usage
```bash
go run main.go migrate-tld -f <file> [-s <host>] [-p <port>] [-d <dbname>] [-u <user>] [-w <password>] [flags]
```

### Example of usage
```bash
go run main.go -f example.csv
```

## Flags
```bash
-d, --dbname string   postgres database name (default "tdpdb")
-f, --file string     path to the csv file
-h, --help            help for migrate-tld
-s, --host string     postgres host (default "localhost")
-w, --pass string     postgres password (DO NOT USE flag for PROD credentials, use prompt instead)
-p, --port int        postgres port (default 5432)
-t, --timeout int     postgres database connection timeout in seconds (default 5)
-u, --user string     postgres user (DO NOT USE flag for PROD credentials, use prompt instead)
```
