SET TIMEZONE = 'UTC';

-- job checks the date of a record in history schema and irreversibly_delete_data()

/* Disabling cron job untill it is closer to 18 month of storage time then we need to revisit 
    SELECT cron.schedule(
    'irreversibly delete data daily at midnight',
    '2 0 * * * UTC',
    $$ SELECT history.irreversibly_delete_data(); $$);
*/ 

-- example to set up cron job
--SELECT cron.schedule(
--    'update all the cost_price tables with is_current flag',
--    '0 0 * * * UTC', 
--    $$ select public.update_is_current(); $$);