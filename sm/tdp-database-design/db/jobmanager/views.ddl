DROP VIEW IF EXISTS v_job;
CREATE OR REPLACE VIEW v_job AS
    SELECT 
        j.id AS job_id,
        j.parent_id AS job_parent_id,
        j.tenant_customer_id,
        js.name AS job_status_name,
        jt.name AS job_type_name,
        j.created_date,
        j.start_date,
        j.end_date,
        j.retry_count,
        j.reference_id,
        jt.reference_table,
        j.result_message AS result_message,
        j.result_data AS result_data,
        j.data AS data,
        TO_JSONB(vtc.*) AS tenant_customer,
        jt.routing_key,
        jt.is_noop AS job_type_is_noop,
        js.is_final AS job_status_is_final,
        js.is_success AS job_status_is_success,
        j.event_id,
        j.is_hard_fail
    FROM job j 
        JOIN job_status js ON j.status_id = js.id 
        JOIN job_type jt ON jt.id = j.type_id
        JOIN v_tenant_customer vtc ON vtc.id = j.tenant_customer_id
;


DROP VIEW IF EXISTS v_job_history;
CREATE OR REPLACE VIEW v_job_history AS 
    SELECT 
        at.created_date,
        at.statement_date,
        at.operation,
        jt.name AS job_type_name,
        at.object_id AS job_id,
        js.name AS status_name,
        at.new_value->'event_id' AS event_id
    FROM audit_trail_log at 
        JOIN job_status js ON js.id = COALESCE(at.new_value->'status_id',at.old_value->'status_id')::UUID
        JOIN job_type jt ON jt.id= COALESCE(at.new_value->'type_id',at.old_value->'type_id')::UUID
    WHERE at.table_name='job' ORDER BY created_date ;
