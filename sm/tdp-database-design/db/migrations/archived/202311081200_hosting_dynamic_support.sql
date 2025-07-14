-- following tables were added to store hosting components for a product

CREATE TABLE IF NOT EXISTS hosting_component_type (
  id        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name      TEXT NOT NULL,
  descr     TEXT,
  UNIQUE (name)
);

CREATE TABLE IF NOT EXISTS hosting_component (
  id        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  type_id   UUID NOT NULL REFERENCES hosting_component_type,
  name      TEXT NOT NULL,
  descr     TEXT,
  UNIQUE (name)
);

CREATE TABLE IF NOT EXISTS hosting_product_component (
    id              UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    product_id      UUID NOT NULL REFERENCES hosting_product,
    component_id    UUID NOT NULL REFERENCES hosting_component
) inherits (class.audit_trail);


-- function was updated to include hosting components in hosting provision job

CREATE OR REPLACE FUNCTION provision_hosting_create_job() RETURNS TRIGGER AS $$
    DECLARE
        v_hosting RECORD;
        v_cuser RECORD;
    BEGIN

        -- find single customer user (temporary)
        SELECT *
        INTO v_cuser
        FROM v_customer_user vcu
        JOIN v_tenant_customer vtnc ON vcu.customer_id = vtnc.customer_id
        WHERE vtnc.id = NEW.tenant_customer_id 
        LIMIT 1;

        WITH components AS (
          SELECT  JSON_AGG(
                    JSONB_BUILD_OBJECT(
                      'name', hc.name,
                      'type', tc_name_from_id('hosting_component_type', hc.type_id)
                    )
                  ) AS data   
          FROM hosting_component hc
          JOIN hosting_product_component hpc ON hpc.component_id = hc.id
          JOIN provision_hosting_create ph ON ph.product_id = hpc.product_id 
          WHERE ph.id = NEW.id
        )
        SELECT
          NEW.id as provision_hosting_create_id,
          vtnc.id AS tenant_customer_id,
          ph.domain_name,
          ph.product_id,
          ph.region_id,
          vtnc.name as customer_name,
          v_cuser.email as customer_email,
          TO_JSONB(hc.*) AS client,
          TO_JSONB(hcrt.*) AS certificate,
          components.data AS components
        INTO v_hosting
        FROM provision_hosting_create ph
        JOIN components ON TRUE
        JOIN hosting_client hc ON hc.id = ph.client_id
        LEFT OUTER JOIN hosting_certificate hcrt ON hcrt.id = PH.certificate_id
        JOIN v_tenant_customer vtnc ON vtnc.id = ph.tenant_customer_id
        WHERE ph.id = NEW.id;

        UPDATE provision_hosting_create SET job_id = job_create(
            v_hosting.tenant_customer_id,
            'provision_hosting_create',
            NEW.id,
            to_jsonb(v_hosting.*)
            ) WHERE id = NEW.id;

        RETURN NEW;
    END;
$$ LANGUAGE plpgsql;
