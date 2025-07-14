# Metadata

In order to support tracing and other future functionality, a column 'metadata' has been 
added to the order table. Json data inserted into this column will be propogated through the db, eventually ending up in the 'data' column of whatever jobs are spawned by the order. It is available to any service accessing the job, and will also be included in the pg_notify notification sent out to the job scheduler when the job is created.