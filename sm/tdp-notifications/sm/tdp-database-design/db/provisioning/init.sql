INSERT INTO provision_status(name,descr,is_success,is_final)
    VALUES
        ('pending','pending provisioning',true,false),
        ('processing','processing',false,false),
        ('completed','completed successfully',true,true),
        ('failed','failed request',false,true),
        ('pending_action','pending an event',false,false);

-- Job reference status overrides per reference table
INSERT INTO job_reference_status_override(status_id, reference_status_table, reference_status_id) VALUES
(tc_id_from_name('job_status','completed_conditionally'), 'provision_status', tc_id_from_name('provision_status','pending_action'));
