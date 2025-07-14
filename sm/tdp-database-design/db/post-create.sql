-- Configure cron only if the extension has been enabled
DO
$$
BEGIN
    PERFORM extname FROM pg_extension WHERE extname = 'pg_cron';

    IF FOUND THEN
        PERFORM cron.schedule('auto partition creator for partitioned tables', '0 6 1 * *', $C$SELECT cron_partition_helper_by_month();$C$);
        -- runs every month on 1st at 6.00 am  
        UPDATE cron.job
        SET database = current_database()
        WHERE jobname = 'create partitions for partitioned tables';
    END IF;
END;
$$;

\i post-views.ddl