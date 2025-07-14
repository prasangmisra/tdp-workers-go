--
-- table: currency
-- description: this table lists all known currencies
--

CREATE TABLE currency (
  id           UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name         TEXT NOT NULL UNIQUE,
  descr        TEXT,
  fraction     INT NOT NULL DEFAULT 1
) INHERITS (class.audit);


-- TODO: Populate table 'currency'.

INSERT INTO currency(name,descr,fraction) VALUES ('USD', 'US Dollar', 100) ON CONFLICT DO NOTHING;

--
-- table: order_price
-- description: price data (price and currency) for the order
--

CREATE TABLE order_price(
  id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  order_id            UUID NOT NULL REFERENCES "order",
  order_item_id       UUID NOT NULL,
  tenant_customer_id  UUID NOT NULL REFERENCES tenant_customer,
  currency_id         UUID NOT NULL REFERENCES currency,
  price               FLOAT NOT NULL
);

--------------------- Order----------------------------------------
DROP VIEW IF EXISTS v_order_item_price;
CREATE OR REPLACE VIEW v_order_item_price AS
SELECT
    op.order_item_id,
    op.order_id,
    op.price,
    c.id AS currency_id,
    c.name AS currency_code,
    c.descr AS currency_descr,
    c.fraction AS currency_fraction,
    o.tenant_customer_id,
    p.name AS product_name,
    ot.name AS order_type_name
FROM order_price op
JOIN currency c ON c.id = op.currency_id
JOIN "order" o ON o.id=op.order_id
JOIN order_type ot ON ot.id = o.type_id 
JOIN product p ON p.id=ot.product_id
;

-- function: order_set_metadata()
-- description: Update order metadata by adding order id;
CREATE OR REPLACE FUNCTION order_set_metadata() RETURNS TRIGGER AS $$
BEGIN
  UPDATE "order" SET metadata = metadata || JSONB_BUILD_OBJECT ('order_id', NEW.id) WHERE id = NEW.id;
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

-- function: plan_create_domain_provision_domain()
-- description: create a domain based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
  v_create_domain   RECORD;
  v_pd_id           UUID;
  v_parent_id       UUID;
  v_locks_required_changes jsonb;
  v_order_item_plan_ids UUID[];
BEGIN
  -- order information
  SELECT * INTO v_create_domain
  FROM v_order_create_domain
  WHERE order_item_id = NEW.order_item_id;

  WITH pd_ins AS (
    INSERT INTO provision_domain(
      domain_name,
      registration_period,
      accreditation_id,
      accreditation_tld_id,
      tenant_customer_id,
      auto_renew,
      pw,
      order_metadata
    ) VALUES(
      v_create_domain.domain_name,
      v_create_domain.registration_period,
      v_create_domain.accreditation_id,
      v_create_domain.accreditation_tld_id,
      v_create_domain.tenant_customer_id,
      v_create_domain.auto_renew,
      COALESCE(v_create_domain.auth_info, TC_GEN_PASSWORD(16)),
      v_create_domain.order_metadata
    ) RETURNING id
  )
  SELECT id INTO v_pd_id FROM pd_ins;

  SELECT
    jsonb_object_agg(key, value)
  INTO v_locks_required_changes FROM jsonb_each(v_create_domain.locks) WHERE value::BOOLEAN = TRUE;

  IF NOT is_jsonb_empty_or_null(v_locks_required_changes) THEN
    WITH inserted_domain_update AS (
      INSERT INTO provision_domain_update(
        domain_name,
        accreditation_id,
        accreditation_tld_id,
        tenant_customer_id,
        order_metadata,
        order_item_plan_ids,
        locks
      ) VALUES (
        v_create_domain.domain_name,
        v_create_domain.accreditation_id,
        v_create_domain.accreditation_tld_id,
        v_create_domain.tenant_customer_id,
        v_create_domain.order_metadata,
        ARRAY[NEW.id],
        v_locks_required_changes
      ) RETURNING id
    )
    SELECT id INTO v_parent_id FROM inserted_domain_update;
  ELSE
    v_order_item_plan_ids := ARRAY [NEW.id];
  END IF;

  -- insert contacts
  INSERT INTO provision_domain_contact(
    provision_domain_id,
    contact_id,
    contact_type_id
  ) ( 
    SELECT 
      v_pd_id, 
      order_contact_id,
      domain_contact_type_id
    FROM create_domain_contact
    WHERE create_domain_id = NEW.order_item_id
  );

  -- insert hosts
  INSERT INTO provision_domain_host(
    provision_domain_id,
    host_id
  ) (
    SELECT
      v_pd_id,
      h.id
    FROM ONLY host h
    JOIN order_host oh ON oh.name = h.name
    JOIN create_domain_nameserver cdn ON cdn.host_id = oh.id
    WHERE cdn.create_domain_id = NEW.order_item_id AND oh.tenant_customer_id = h.tenant_customer_id
  );

  UPDATE provision_domain 
  SET is_complete = TRUE, order_item_plan_ids = v_order_item_plan_ids, parent_id = v_parent_id 
  WHERE id = v_pd_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--------------------- provision ----------------------------------------
-- function: provision_domain_job()
-- description: creates the job to create the domain
CREATE OR REPLACE FUNCTION provision_domain_job() RETURNS TRIGGER AS $$
DECLARE
  v_domain     RECORD;
BEGIN
  WITH contacts AS (
    SELECT JSONB_AGG(
      JSONB_BUILD_OBJECT(
        'type',ct.name,
        'handle',pc.handle
      )
    ) AS data
    FROM provision_domain pd
      JOIN provision_domain_contact pdc
        ON pdc.provision_domain_id=pd.id
      JOIN domain_contact_type ct ON ct.id=pdc.contact_type_id
      JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
      JOIN provision_status ps ON ps.id = pc.status_id
    WHERE
      ps.is_success AND ps.is_final
      AND pd.id = NEW.id
  ),
  hosts AS (
    SELECT JSONB_AGG(data) AS data
    FROM
      (SELECT JSONB_BUILD_OBJECT(
        'name',
        h.name,
        'ip_addresses',
        jsonb_agg(ha.address)
      ) as data
      FROM provision_domain pd
        JOIN provision_domain_host pdh ON pdh.provision_domain_id=pd.id
        JOIN host h ON h.id = pdh.host_id
        JOIN provision_host ph ON ph.host_id = h.id
        JOIN provision_status ps ON ps.id = ph.status_id
        join host_addr ha on h.id = ha.host_id
      WHERE
        ps.is_success AND ps.is_final
        AND pdh.provision_domain_id=NEW.id
      GROUP BY h.name) sub_q
  ), 
  price AS (
    SELECT
      JSONB_BUILD_OBJECT(
        'amount', op.price, 
        'currency', c.name, 
        'fraction', c.fraction
    ) AS data
    FROM provision_domain pd
    JOIN v_order_create_domain vcd ON vcd.domain_name = pd.domain_name
    JOIN order_price op ON op.order_item_id = vcd.order_item_id AND op.order_id = vcd.order_id
    JOIN currency c ON c.id = op.currency_id
    WHERE vcd.domain_name = NEW.domain_name
  )
  SELECT
    NEW.id AS provision_contact_id,
    tnc.id AS tenant_customer_id,
    d.domain_name AS name,
    d.registration_period,
    d.pw AS pw,
    contacts.data AS contacts,
    hosts.data AS nameservers,
    price.data AS price,
    TO_JSONB(a.*) AS accreditation,
    TO_JSONB(vat.*) AS accreditation_tld,
    d.order_metadata AS metadata
  INTO v_domain
  FROM provision_domain d
    JOIN contacts ON TRUE
    JOIN hosts ON TRUE
    LEFT JOIN price ON TRUE
    JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
    JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
    JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
  WHERE d.id = NEW.id;

  UPDATE provision_domain SET
    job_id = job_submit(
    v_domain.tenant_customer_id,
    'provision_domain_create',
    NEW.id,
    TO_JSONB(v_domain.*)
  ) WHERE id=NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

