SET search_path TO public,class;
--
-- table: provision_status
-- description: various statuses when provisioning 
--

CREATE TABLE provision_status (
  id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  descr       TEXT,
  is_success  BOOLEAN NOT NULL,
  is_final    BOOLEAN NOT NULL,
  UNIQUE (name)
);


--
-- table: class.provision
-- description: when an object needs to be provisioned in the backend
--              it will require certain fields which are covered by
--              this table.
--
-- When an order_item_plan is being processed and it determines that 
-- the object needs to be provisioned 
-- 
-- if the provisioning fails, there should be a stored procedure that
-- 1. notifies the order_item_plan about the failure by setting the
--    appropriate status AND passing along the result_message and result_data
-- 2. deletes the row from the provision_* so it can be retried again if needed.
--    the record will be stored in the audit_trail table
-- 

CREATE TABLE class.provision (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_customer_id      UUID NOT NULL REFERENCES tenant_customer,
  provisioned_date        TIMESTAMPTZ,
  status_id               UUID NOT NULL DEFAULT tc_id_from_name('provision_status','pending') 
                          REFERENCES provision_status,
  attempt_count           INT DEFAULT 1,
  allowed_attempts        INT DEFAULT 1,
  roid                    TEXT,
  job_id                  UUID REFERENCES job,
  order_item_plan_ids     UUID[],
  order_metadata          JSONB DEFAULT '{}'::JSONB,
  result_message          TEXT,
  result_data             JSONB
);


COMMENT ON COLUMN provision.order_item_plan_ids IS 'order_item_plan_id''s that need to be notified (Via UPDATE) when this transaction completes';

\i update_domain.ddl
\i create_domain.ddl
\i renew_domain.ddl
\i redeem_domain.ddl
\i delete_domain.ddl
\i transfer_in_domain.ddl
\i transfer_away_domain.ddl
\i create_contact.ddl
\i update_contact.ddl
\i delete_contact.ddl
\i create_host.ddl
\i update_host.ddl
\i create_hosting.ddl
\i delete_hosting.ddl
\i update_hosting.ddl
\i delete_host.ddl
