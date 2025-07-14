-- function: provision_contact_job()
-- description: creates the job to create the contact
CREATE OR REPLACE FUNCTION provision_contact_job() RETURNS TRIGGER AS $$
DECLARE
    v_contact       RECORD;
    v_rdp_enabled   BOOLEAN;
BEGIN

    SELECT get_tld_setting(
        p_key => 'tld.order.rdp_enabled',
        p_accreditation_tld_id => NEW.accreditation_tld_id
   ) INTO v_rdp_enabled;

    SELECT
        NEW.id AS provision_contact_id,
        NEW.tenant_customer_id AS tenant_customer_id,
        CASE WHEN v_rdp_enabled THEN
            jsonb_select_contact_data_by_id(
                c.id,
                CASE
                WHEN vat.tld_id IS NOT NULL THEN
                    get_domain_data_elements_for_permission(
                        p_tld_id => vat.tld_id,
                        p_data_element_parent_name => tc_name_from_id('domain_contact_type', NEW.domain_contact_type_id),
                        p_permission_name => 'transmit_to_registry'
                    )
                END
            )
        ELSE
            jsonb_get_contact_by_id(c.id)
        END AS contact,
        TO_JSONB(a.*) AS accreditation,
        NEW.pw AS pw,
        NEW.order_metadata AS metadata
    INTO v_contact
    FROM ONLY contact c
    JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
    LEFT JOIN v_accreditation_tld vat ON vat.accreditation_id = NEW.accreditation_id
    AND vat.accreditation_tld_id = NEW.accreditation_tld_id
    WHERE c.id=NEW.contact_id;

    UPDATE provision_contact SET job_id=job_submit(
        NEW.tenant_customer_id,
        'provision_contact_create',
        NEW.id,
        TO_JSONB(v_contact.*)
    ) WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_contact_update_job()
-- description: creates contact update parent and child jobs
CREATE OR REPLACE FUNCTION provision_contact_update_job() RETURNS TRIGGER AS $$
DECLARE
    _parent_job_id      UUID;
    _child_job          RECORD;
    v_contact           RECORD;
BEGIN
    SELECT job_create(
                   NEW.tenant_customer_id,
                   'provision_contact_update',
                   NEW.id,
                   to_jsonb(NULL::jsonb)
           ) INTO _parent_job_id;

    UPDATE provision_contact_update SET job_id= _parent_job_id
    WHERE id = NEW.id;

    FOR _child_job IN
        SELECT pdcu.*
        FROM provision_domain_contact_update pdcu
                 JOIN provision_status ps ON ps.id = pdcu.status_id
        WHERE pdcu.provision_contact_update_id = NEW.id AND
            ps.id = tc_id_from_name('provision_status','pending')
        LOOP
            SELECT
                _child_job.id AS provision_domain_contact_update_id,
                _child_job.tenant_customer_id AS tenant_customer_id,
                jsonb_get_order_contact_by_id(c.id) AS contact,
                TO_JSONB(a.*) AS accreditation,
                _child_job.handle AS handle
            INTO v_contact
            FROM ONLY order_contact c
                     JOIN v_accreditation a ON  a.accreditation_id = _child_job.accreditation_id
            WHERE c.id=_child_job.order_contact_id;

            UPDATE provision_domain_contact_update SET job_id=job_submit(
                    _child_job.tenant_customer_id,
                    'provision_domain_contact_update',
                    _child_job.id,
                    to_jsonb(v_contact.*),
                    _parent_job_id,
                    NOW(),
                    FALSE
                                                              ) WHERE id = _child_job.id;
        END LOOP;

    -- all child jobs are failed, fail the parent job
    IF NOT FOUND THEN
        UPDATE job
        SET status_id= tc_id_from_name('job_status', 'failed')
        WHERE id = _parent_job_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: provision_contact_delete_job()
-- description: creates contact delete parent and child jobs
CREATE OR REPLACE FUNCTION provision_contact_delete_job() RETURNS TRIGGER AS $$
DECLARE
    _parent_job_id      UUID;
    _child_jobs         RECORD;
    v_contact           RECORD;
BEGIN
    SELECT job_create(
                   NEW.tenant_customer_id,
                   'provision_contact_delete_group',
                   NEW.id,
                   to_jsonb(NULL::jsonb)
           ) INTO _parent_job_id;

    UPDATE provision_contact_delete SET job_id= _parent_job_id WHERE id = NEW.id;

    FOR _child_jobs IN
        SELECT *
        FROM provision_contact_delete pcd
        WHERE pcd.parent_id = NEW.id
        LOOP
            SELECT
                TO_JSONB(a.*) AS accreditation,
                _child_jobs.handle AS handle,
                _child_jobs.order_metadata AS metadata
            INTO v_contact
            FROM v_accreditation a
            WHERE a.accreditation_id = _child_jobs.accreditation_id;

            UPDATE provision_contact_delete SET job_id=job_submit(
                    _child_jobs.tenant_customer_id,
                    'provision_contact_delete',
                    _child_jobs.id,
                    to_jsonb(v_contact.*),
                    _parent_job_id,
                    NOW(),
                    FALSE
                                                       ) WHERE id = _child_jobs.id;
        END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
