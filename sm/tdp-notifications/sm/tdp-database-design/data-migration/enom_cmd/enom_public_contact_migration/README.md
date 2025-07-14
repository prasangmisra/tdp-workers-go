# Enom Public Contact Migration


This Package will extract the public contact information from Identity Service for Enom Domains, and store them in TDP.

## Prerequisites
* Enom Database ODBC Database Connection
* Postgres ODBC Database Connection (TDP or Local instance)


## Project Parameters
* `Enom_NameHost_ODBC_Connectionstring`: The connection string representing the Enom Database DSN (uid/Dsn are the only requirements)
	* Example: `uid=adam;dsn=NameHost;`
	
*  `Enom_NameHost_ODBC_Password`: The password for the Enom ODBC DSN
	
* `GetDomainListQuery`: The SQL Query to retrieve the list of domains from the Enom Database
	* Example: `SELECT TOP 10 [DomainNameID], [TLD], [SldDotTld], [RRProcessor] FROM domains WHERE TLD = 'sexy'`
		* Note: The query must return the columns `DomainNameID`, `TLD`, `SldDotTld`, and `RRProcessor` in the order above.

* `Tdpdb_dev_Connectionstring`: The connection string representing the TDP database in dev environment (uid/Dsn are the only requirements)
	* Example: `uid=adam;dsn=tdpdb_dev;`
	
* `Tdpdb_dev_Password`: The password for the TDP Dev ODBC DSN

* `Tdpdb_local_Connectionstring`: The connection string representing the TDP database in your local environment (uid/Dsn are the only requirements)
	* Example: `uid=adam;dsn=tdpdb_local;`

* `Tdpdb_local_Password`: The password for the TDP local ODBC DSN

* `IdentityEndpoint`: The URL for the Identity Service API

* `IdentityOperation`: The URI segment for the Identity Service API operation

* `IdentityPath`: The URI segment for the Identity Service API path

* `IdentityApiKey`: The API Key for the Identity Service API

* `IdentitySystemName`: The system name used by Identity Service to find the correct contact data (relates loosely to reseller_id)

* `UseLocalTdpDb`: A bool to indicate whether results should be written to the development TDP database, or to your local TDP database. 
	* Set to "true" to write to your local TDP database rather than Dev



## Project Variables

* `FireDebugEvents`: A bool to indicate whether Informational Events should be logged in the package's Execution Progress section
	* Set to "true" to enable debug events

* `IdentityBatchRequestSize`: The number of requests to send to the Identity Service at one time.
	* For now, this number should be kept under 1000 to avoid DDOS'ing Identity. 80 is the default, and preferred number for dev testing.

* `ResultSet` This variable holds the result set from the Execute SQL Task titled "GetDomains"