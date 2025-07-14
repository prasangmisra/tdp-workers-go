	
	UPDATE public.domain SET migration_info = metadata, metadata='{}'::jsonb
	WHERE (migration_info ='{}'::jsonb OR migration_info IS NULL)  AND 
		(metadata ? 'migration_info' OR metadata ? 'min_nameservers_issue' OR metadata ? 'allowed_nameserver_count_issue');			
	
    
	UPDATE public.contact SET migration_info = metadata, metadata='{}'::jsonb
	WHERE (migration_info ='{}'::jsonb OR migration_info IS NULL)  AND 
		(metadata ? 'migration_info' OR metadata ? 'data_source');	

	
	
	

	
	
	
	
