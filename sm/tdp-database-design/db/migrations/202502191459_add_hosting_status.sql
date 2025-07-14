BEGIN;
--
-- table: hosting_status
-- description: this table lists the possible hosting statuses.
--

CREATE TABLE hosting_status (
    id         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name       TEXT NOT NULL,
    descr      TEXT NOT NULL,
    UNIQUE (name)
);

INSERT INTO hosting_status (name, descr)
VALUES
    ('Pending DNS', 'Hosting is pending for DNS Setup'),
    ('Pending Certificate Setup', 'Hosting is pending for Certificate Setup'),
    ('Requested', 'Hosting was requested'),
    ('In progress', 'Hosting creation is in progress'),
    ('Completed', 'Hosting creation is completed'),
    ('Failed', 'Hosting creation failed'),
    ('Failed Certificate Renewal', 'Hosting failed on certificate renewal'),
    ('Cancelled', 'Hosting creation was cancelled');

---------------- backward compatibility of status and hosting_status_id ----------------

CREATE OR REPLACE FUNCTION force_hosting_status_id_from_name() RETURNS TRIGGER AS $$
BEGIN

    IF NEW.status IS NOT NULL THEN
        NEW.hosting_status_id = tc_id_from_name('hosting_status', NEW.status);
    ELSE
        NEW.hosting_status_id = NULL;
    END IF;

RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION force_hosting_status_name_from_id() RETURNS TRIGGER AS $$
BEGIN

    IF NEW.hosting_status_id IS NOT NULL THEN
        NEW.status = tc_name_from_id('hosting_status', NEW.hosting_status_id);
    ELSE
        NEW.status = NULL;
    END IF;

RETURN NEW;
END;
$$ LANGUAGE plpgsql;

------------------------------------ hosting ------------------------------------

-- 'In Progress' was renamed to 'In progress'
UPDATE hosting SET status = 'In progress' WHERE status = 'In Progress';

-- make status column reference hosting_status table
ALTER TABLE hosting
    ADD FOREIGN KEY (status) REFERENCES hosting_status (name);

-- add hosting_status_id column to hosting table and order_item_create_hosting child table
ALTER TABLE hosting
ADD COLUMN IF NOT EXISTS hosting_status_id UUID REFERENCES hosting_status;


CREATE TRIGGER hosting_insert_hosting_status_id_from_name_tg
    BEFORE INSERT ON hosting
    FOR EACH ROW WHEN ( NEW.hosting_status_id IS NULL AND NEW.status IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_id_from_name();

CREATE TRIGGER hosting_update_hosting_status_id_from_name_tg
    BEFORE UPDATE OF status ON hosting
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_id_from_name();


CREATE TRIGGER hosting_insert_hosting_status_name_from_id_tg
    BEFORE INSERT ON hosting
    FOR EACH ROW WHEN ( NEW.status IS NULL AND NEW.hosting_status_id IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_name_from_id();

CREATE TRIGGER hosting_update_hosting_status_name_from_id_tg
    BEFORE UPDATE OF hosting_status_id ON hosting
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_name_from_id();


-- populate hosting_status_id column based on status column
UPDATE ONLY hosting SET hosting_status_id = tc_id_from_name('hosting_status', status) WHERE status <> '';

------------------------------------ order_item_create_hosting ------------------------------------

ALTER TABLE order_item_create_hosting
    ADD FOREIGN KEY (status) REFERENCES hosting_status (name);

CREATE TRIGGER order_item_create_hosting_insert_hosting_status_id_from_name_tg
    BEFORE INSERT ON order_item_create_hosting
    FOR EACH ROW WHEN ( NEW.hosting_status_id IS NULL AND NEW.status IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_id_from_name();

CREATE TRIGGER order_item_create_hosting_update_hosting_status_id_from_name_tg
    BEFORE UPDATE OF status ON order_item_create_hosting
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_id_from_name();


CREATE TRIGGER order_item_create_hosting_insert_hosting_status_name_from_id_tg
    BEFORE INSERT ON order_item_create_hosting
    FOR EACH ROW WHEN ( NEW.status IS NULL AND NEW.hosting_status_id IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_name_from_id();

CREATE TRIGGER order_item_create_hosting_update_hosting_status_name_from_id_tg
    BEFORE UPDATE OF hosting_status_id ON order_item_create_hosting
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_name_from_id();


-- populate hosting_status_id column based on status column
UPDATE order_item_create_hosting SET hosting_status_id = tc_id_from_name('hosting_status', status) WHERE status <> '';

------------------------------------ provision_hosting_create ------------------------------------

-- 'In Progress' was renamed to 'In progress'
UPDATE provision_hosting_create SET status = 'In progress' WHERE status = 'In Progress';

-- make status column reference hosting_status table
ALTER TABLE provision_hosting_create
    ADD FOREIGN KEY (status) REFERENCES hosting_status (name);

-- add hosting_status_id column to provision_hosting_create table
ALTER TABLE provision_hosting_create
ADD COLUMN IF NOT EXISTS hosting_status_id UUID REFERENCES hosting_status;


CREATE TRIGGER provision_hosting_create_insert_hosting_status_id_from_name_tg
    BEFORE INSERT ON provision_hosting_create
    FOR EACH ROW WHEN ( NEW.hosting_status_id IS NULL AND NEW.status IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_id_from_name();

CREATE TRIGGER provision_hosting_create_update_hosting_status_id_from_name_tg
    BEFORE UPDATE OF status ON provision_hosting_create
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_id_from_name();


CREATE TRIGGER provision_hosting_create_insert_hosting_status_name_from_id_tg
    BEFORE INSERT ON provision_hosting_create
    FOR EACH ROW WHEN ( NEW.status IS NULL AND NEW.hosting_status_id IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_name_from_id();

CREATE TRIGGER provision_hosting_create_update_hosting_status_name_from_id_tg
    BEFORE UPDATE OF hosting_status_id ON provision_hosting_create
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_name_from_id();


-- populate hosting_status_id column based on status column
UPDATE provision_hosting_create SET hosting_status_id = tc_id_from_name('hosting_status', status) WHERE status <> '';

------------------------------------ provision_hosting_delete ------------------------------------

-- 'In Progress' was renamed to 'In progress'
UPDATE provision_hosting_delete SET status = 'In progress' WHERE status = 'In Progress';

-- make status column reference hosting_status table
ALTER TABLE provision_hosting_delete
    ADD FOREIGN KEY (status) REFERENCES hosting_status (name);

-- add hosting_status_id column to provision_hosting_delete table
ALTER TABLE provision_hosting_delete
ADD COLUMN IF NOT EXISTS hosting_status_id UUID REFERENCES hosting_status;


CREATE TRIGGER provision_hosting_delete_insert_hosting_status_id_from_name_tg
    BEFORE INSERT ON provision_hosting_delete
    FOR EACH ROW WHEN ( NEW.hosting_status_id IS NULL AND NEW.status IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_id_from_name();

CREATE TRIGGER provision_hosting_delete_update_hosting_status_id_from_name_tg
    BEFORE UPDATE OF status ON provision_hosting_delete
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_id_from_name();


CREATE TRIGGER provision_hosting_delete_insert_hosting_status_name_from_id_tg
    BEFORE INSERT ON provision_hosting_delete
    FOR EACH ROW WHEN ( NEW.status IS NULL AND NEW.hosting_status_id IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_name_from_id();

CREATE TRIGGER provision_hosting_delete_update_hosting_status_name_from_id_tg
    BEFORE UPDATE OF hosting_status_id ON provision_hosting_delete
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_name_from_id();


-- populate hosting_status_id column based on status column
UPDATE provision_hosting_delete SET hosting_status_id = tc_id_from_name('hosting_status', status) WHERE status <> '';

------------------------------------ provision_hosting_update ------------------------------------

-- 'In Progress' was renamed to 'In progress'
UPDATE provision_hosting_update SET status = 'In progress' WHERE status = 'In Progress';

-- make status column reference hosting_status table
ALTER TABLE provision_hosting_update
    ADD FOREIGN KEY (status) REFERENCES hosting_status (name);

-- add hosting_status_id column to provision_hosting_update table
ALTER TABLE provision_hosting_update
    ADD COLUMN IF NOT EXISTS hosting_status_id UUID REFERENCES hosting_status;


CREATE TRIGGER provision_hosting_update_insert_hosting_status_id_from_name_tg
    BEFORE INSERT ON provision_hosting_update
    FOR EACH ROW WHEN ( NEW.hosting_status_id IS NULL AND NEW.status IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_id_from_name();

CREATE TRIGGER provision_hosting_update_update_hosting_status_id_from_name_tg
    BEFORE UPDATE OF status ON provision_hosting_update
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_id_from_name();


CREATE TRIGGER provision_hosting_update_insert_hosting_status_name_from_id_tg
    BEFORE INSERT ON provision_hosting_update
    FOR EACH ROW WHEN ( NEW.status IS NULL AND NEW.hosting_status_id IS NOT NULL)
    EXECUTE PROCEDURE force_hosting_status_name_from_id();

CREATE TRIGGER provision_hosting_update_update_hosting_status_name_from_id_tg
    BEFORE UPDATE OF hosting_status_id ON provision_hosting_update
    FOR EACH ROW EXECUTE PROCEDURE force_hosting_status_name_from_id();


-- populate hosting_status_id column based on status column
UPDATE provision_hosting_update SET hosting_status_id = tc_id_from_name('hosting_status', status) WHERE status <> '';

--------------------------------------------------------------------------------

-- UPDATE function: cancel_hosting_provision()
-- description: cancels hosting provisioning at certificate provisioning stage
CREATE OR REPLACE FUNCTION cancel_hosting_provision(_hosting_id UUID) RETURNS void AS $$
DECLARE
_provision_hosting_certificate_create RECORD;
    _provision_hosting_dns_check_job RECORD;
    _provision_hosting_certificate_create_job RECORD;
BEGIN
    -- find coresponsding provision record
    SELECT * INTO _provision_hosting_certificate_create
    FROM provision_hosting_certificate_create phcc
             JOIN provision_status ps ON ps.id = phcc.status_id
    WHERE phcc.hosting_id = _hosting_id
      AND ps.is_final = FALSE
        FOR UPDATE;

    IF NOT FOUND THEN
            RAISE EXCEPTION 'Hosting provisioning cannot be cancelled at this stage' USING ERRCODE = 'data_exception';
    END IF;

        -- mark provision record as failed
    UPDATE provision_hosting_certificate_create
    SET status_id = tc_id_from_name('provision_status', 'failed')
    WHERE id = _provision_hosting_certificate_create.id;

    -- override hosting status
    UPDATE ONLY hosting
    SET hosting_status_id = tc_id_from_name('hosting_status', 'Cancelled')
    WHERE id = _provision_hosting_certificate_create.hosting_id;

    -- cleanup jobs
    SELECT * INTO _provision_hosting_dns_check_job
    FROM job
    WHERE reference_id = _provision_hosting_certificate_create.id
      AND type_id = tc_id_from_name('job_type', 'provision_hosting_dns_check')
      AND NOT EXISTS (
        SELECT 1
        FROM job_status js
        WHERE js.id = job.status_id
          AND js.is_final = TRUE
    ) FOR UPDATE;

    IF FOUND THEN
            -- mark dns check job as failed and prevent from starting again
    UPDATE job SET
                   status_id = tc_id_from_name('job_status', 'failed'),
                   retry_count = max_retries
    WHERE id = _provision_hosting_dns_check_job.id;
    END IF;

    SELECT * INTO _provision_hosting_certificate_create_job
    FROM job
    WHERE reference_id = _provision_hosting_certificate_create.id
      AND type_id = tc_id_from_name('job_type', 'provision_hosting_certificate_create')
      AND NOT EXISTS (
        SELECT 1
        FROM job_status js
        WHERE js.id = job.status_id
          AND js.is_final = TRUE
    ) FOR UPDATE;

    IF FOUND THEN
            -- mark create certificate job as failed
    UPDATE job SET
        status_id = tc_id_from_name('job_status', 'failed')
    WHERE id = _provision_hosting_certificate_create_job.id;
    END IF;

END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------

-- UPDATE function: order_item_create_hosting_record()
-- description: creates the hosting object which we will manipulate during order processing
CREATE OR REPLACE FUNCTION order_item_create_hosting_record() RETURNS TRIGGER AS $$
DECLARE
v_hosting_client RECORD;
BEGIN

    SELECT * INTO v_hosting_client
    FROM hosting_client
    WHERE id = NEW.client_id;

    INSERT INTO hosting_client (
        id,
        tenant_customer_id,
        external_client_id,
        name,
        email,
        username,
        password,
        is_active
    ) VALUES (
                 v_hosting_client.id,
                 v_hosting_client.tenant_customer_id,
                 v_hosting_client.external_client_id,
                 v_hosting_client.name,
                 v_hosting_client.email,
                 v_hosting_client.username,
                 v_hosting_client.password,
                 v_hosting_client.is_active
             ) ON CONFLICT DO NOTHING;

    IF NEW.certificate_id IS NOT NULL THEN
            INSERT INTO hosting_certificate (
                SELECT * FROM hosting_certificate WHERE id=NEW.certificate_id
            );
    END IF;

        -- insert all the values from new into hosting
    INSERT INTO hosting (
        id,
        domain_name,
        product_id,
        region_id,
        client_id,
        tenant_customer_id,
        certificate_id,
        external_order_id,
        hosting_status_id,
        descr,
        is_active,
        is_deleted,
        tags,
        metadata
    )
    VALUES (
               NEW.id,
               NEW.domain_name,
               NEW.product_id,
               NEW.region_id,
               NEW.client_id,
               NEW.tenant_customer_id,
               NEW.certificate_id,
               NEW.external_order_id,
               NEW.hosting_status_id,
               NEW.descr,
               NEW.is_active,
               NEW.is_deleted,
               NEW.tags,
               NEW.metadata
           );

    RETURN NEW;
END $$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------

-- UPDATE function: provision_hosting_create_success
-- description: updates the hosting order in the hosting table
CREATE OR REPLACE FUNCTION provision_hosting_create_success() RETURNS TRIGGER AS $$
BEGIN

    WITH hosting_update AS (
    UPDATE ONLY hosting
    SET
        hosting_status_id = NEW.hosting_status_id,
        is_active = NEW.is_active,
        is_deleted = NEW.is_deleted,
        external_order_id = NEW.external_order_id
    WHERE id = NEW.hosting_id
        RETURNING client_id
        )
    UPDATE ONLY hosting_client
    SET
        external_client_id = NEW.external_client_id,
        username = NEW.client_username
    WHERE id = (SELECT client_id FROM hosting_update) AND external_client_id IS NULL;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------

-- UPDATE function: provision_hosting_update_success
-- description: updates the hosting order in the hosting table
CREATE OR REPLACE FUNCTION provision_hosting_update_success() RETURNS TRIGGER AS $$
BEGIN
    UPDATE ONLY hosting h
    SET
        hosting_status_id = COALESCE(NEW.hosting_status_id, h.hosting_status_id),
        is_active = COALESCE(NEW.is_active, h.is_active),
        certificate_id = COALESCE(NEW.certificate_id, h.certificate_id)
    WHERE h.id = NEW.hosting_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------

-- UPDATE function: provision_hosting_delete_success
-- description: updates the hosting order in the hosting table
CREATE OR REPLACE FUNCTION provision_hosting_delete_success() RETURNS TRIGGER AS $$
BEGIN
    UPDATE ONLY hosting h
    SET
        hosting_status_id = COALESCE(NEW.hosting_status_id, h.hosting_status_id),
        is_deleted = COALESCE(NEW.is_deleted, h.is_deleted),
        is_active = COALESCE(NEW.is_active, h.is_active)
    WHERE h.id = NEW.hosting_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------

-- UPDATE function: mark_hosting_record_failed
-- description: marks a hosting record as failed and sets is_deleted to true
CREATE OR REPLACE FUNCTION mark_hosting_record_failed() RETURNS TRIGGER AS $$
BEGIN
    UPDATE ONLY hosting
    SET
        hosting_status_id = tc_id_from_name('hosting_status', 'Failed'),
        is_deleted = TRUE
    WHERE id = NEW.hosting_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-------------------------------------------------------------------------------

-- UPDATE function: provision_hosting_certificate_create_update_hosting_status
-- description: updates the hosting status to 'Pending Certificate Setup'
CREATE OR REPLACE FUNCTION provision_hosting_certificate_create_update_hosting_status() RETURNS TRIGGER AS $$
BEGIN
    UPDATE ONLY hosting
    SET hosting_status_id = tc_id_from_name('hosting_status', 'Pending Certificate Setup')
    WHERE id = NEW.hosting_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


COMMIT;
