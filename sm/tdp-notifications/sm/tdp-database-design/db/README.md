# Database Schema

See `Makefile` for targets and variables.

## Installing pg_prove on Mac OS X

Use the `cpanm` tool—the `cpanminus` installer—to install the tool globally. To this end, this is an example of a fresh installation:

```shell
$ cpanm TAP::Parser::SourceHandler::pgTAP
--> Working on TAP::Parser::SourceHandler::pgTAP
Fetching http://www.cpan.org/authors/id/D/DW/DWHEELER/TAP-Parser-SourceHandler-pgTAP-3.36.tar.gz ... OK
==> Found dependencies: Module::Build
--> Working on Module::Build
Fetching http://www.cpan.org/authors/id/L/LE/LEONT/Module-Build-0.4231.tar.gz ... OK
Configuring Module-Build-0.4231 ... OK
Building and testing Module-Build-0.4231 ... OK
Successfully installed Module-Build-0.4231
Configuring TAP-Parser-SourceHandler-pgTAP-3.36 ... OK
Building and testing TAP-Parser-SourceHandler-pgTAP-3.36 ... OK
Successfully installed TAP-Parser-SourceHandler-pgTAP-3.36
2 distributions installed
```
## Installing pg_prove on Debian

```shell
$ sudo apt install postgresql-pgtap
```
## Installing pg_cron on Debian

```shell
$ sudo apt install postgresql-14-cron libpg-hstore-perl
```

## Use of the pg_cron extension

Automated maintenance of partition tables uses the `pg_cron` extension. This needs to be installed to the database host so that the extension can be enabled. The following changes need to be made to the `postgresql.conf` file in order to enable this extension.

```config
shared_preload_libraries = 'pg_cron'
cron.database_name = tdpdb
```
In Debian you should create a file /etc/postgresql/14/main/conf.d/pg_cron.conf containing the above two lines.

Note that the database user creating the database via Makefile needs superuser rights.