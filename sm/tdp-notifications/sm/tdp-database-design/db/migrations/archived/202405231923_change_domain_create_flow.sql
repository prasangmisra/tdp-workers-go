-- Insert new attribute key
INSERT INTO attr_key(
  name,
  category_id,
  descr,
  value_type_id,
  default_value,
  allow_null)
VALUES(
  'host_ip_required_non_auth',
  (SELECT id FROM attr_category WHERE name='order'),
  'Registry requires host IP addresses',
  (SELECT id FROM attr_value_type WHERE name='BOOLEAN'),
  FALSE::TEXT,
  FALSE
) ON CONFLICT DO NOTHING;

-- function: tld_part
-- description: returns tld for given fqdn (domain name or hostname).
CREATE OR REPLACE FUNCTION tld_part(fqdn TEXT) RETURNS TEXT AS $$
DECLARE
  v_tld TEXT;
BEGIN
  SELECT name INTO v_tld
  FROM tld
  WHERE fqdn LIKE '%' || name
  ORDER BY LENGTH(name) DESC
  LIMIT 1;

  RETURN v_tld;
END;
$$ LANGUAGE plpgsql;


-- function: get_accreditation_tld_by_name
-- description: returns accreditation_tld record by name (domain name or hostname) for an order.
CREATE OR REPLACE FUNCTION get_accreditation_tld_by_name(fqdn TEXT, tc_id UUID) RETURNS RECORD AS $$
DECLARE
  v_tld_name    TEXT;
  v_acc_tld     RECORD;
BEGIN
    v_tld_name := tld_part(fqdn);

    SELECT * INTO v_acc_tld
    FROM v_accreditation_tld
    WHERE tld_name = v_tld_name
      AND tenant_customer_id=tc_id
      AND is_default;

    IF NOT FOUND THEN
      RETURN NULL;
    END IF;
    
    RETURN v_acc_tld;
END;
$$ LANGUAGE PLPGSQL;


-- function: order_item_set_tld_id
-- description: this trigger function will set the NEW.accreditation_tld_id column 
-- based on get_accreditation_tld_by_name(NEW.name, tenant_customer_id)
CREATE OR REPLACE FUNCTION order_item_set_tld_id() RETURNS TRIGGER AS  $$
DECLARE
  tc_id      UUID;
  v_acc_tld  RECORD;
BEGIN
    SELECT tenant_customer_id INTO tc_id FROM "order" WHERE id=NEW.order_id;
    v_acc_tld := get_accreditation_tld_by_name(NEW.name, tc_id);

    IF v_acc_tld IS NULL OR v_acc_tld.accreditation_tld_id IS NULL THEN
      RAISE EXCEPTION 'TLD in the ''%'' domain is not available', NEW.name;
    END IF;

    NEW.accreditation_tld_id = v_acc_tld.accreditation_tld_id;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;


-- function: is_host_provisioned()
-- description: check to see if the host is already provisioned in the instance.
CREATE OR REPLACE FUNCTION is_host_provisioned(acc_id UUID, hostname TEXT) RETURNS BOOLEAN AS $$
BEGIN
  PERFORM TRUE
  FROM provision_host ph
  JOIN host h ON h.id = ph.host_id
  JOIN provision_status ps ON ps.id = ph.status_id
  WHERE
    ph.accreditation_id = acc_id
    AND h.name = hostname
    AND ps.name='completed';
  
  RETURN FOUND;
END;
$$ LANGUAGE plpgsql;


-- function: provision_host()
-- description: provision host under specific accreditation and customer
CREATE OR REPLACE FUNCTION provision_host(acc_id UUID, tc_id UUID, order_item_plan_id UUID, o_metadata JSONB, h_id UUID) RETURNS VOID AS $$
BEGIN
  INSERT INTO provision_host(
    accreditation_id,
    host_id,
    tenant_customer_id,
    order_item_plan_ids,
    order_metadata
  ) VALUES (
    acc_id,
    h_id,
    tc_id,
    ARRAY[order_item_plan_id],
    o_metadata
  ) ON CONFLICT (host_id,accreditation_id)
    DO UPDATE
      SET order_item_plan_ids = provision_host.order_item_plan_ids || EXCLUDED.order_item_plan_ids;
END;
$$ LANGUAGE plpgsql;


-- function: plan_create_domain_provision_host()
-- description: create a host based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_host() RETURNS TRIGGER AS $$
DECLARE
  v_dc_host                                   RECORD;
  v_create_domain                             RECORD;
  v_host_object_supported                     BOOLEAN;
  v_host_parent_domain                        RECORD;
  v_host_accreditation                        RECORD;
  v_host_addrs                                INET[];
  v_host_addrs_empty                          BOOLEAN;
BEGIN
  -- Fetch domain creation host details
  SELECT cdn.*,oh."name",oh.tenant_customer_id,oh.domain_id
  INTO v_dc_host 
  FROM create_domain_nameserver cdn
  JOIN order_host oh ON oh.id=cdn.host_id
  WHERE
    cdn.id = NEW.reference_id;

  IF v_dc_host.id IS NULL THEN
    RAISE EXCEPTION 'reference id % not found in create_domain_nameserver table', NEW.reference_id;
  END IF;

  -- Load the order information
  SELECT * INTO v_create_domain
  FROM v_order_create_domain
  WHERE order_item_id = NEW.order_item_id;

  -- Host provisioning will be skipped if the host object is not supported for domain accreditation.
  SELECT va.value INTO v_host_object_supported
  FROM v_attribute va 
  WHERE va.key = 'tld.order.host_object_supported'
    AND va.tld_id = v_create_domain.tld_id;

  IF v_host_object_supported IS FALSE THEN
    UPDATE create_domain_plan SET status_id = tc_id_from_name('order_item_plan_status', 'completed') WHERE id = NEW.id;
    RETURN NEW;
  END IF;

  -- Host Accreditation
  v_host_accreditation := get_accreditation_tld_by_name(v_dc_host.name, v_dc_host.tenant_customer_id);

  IF v_host_accreditation IS NULL OR v_host_accreditation.accreditation_id IS NULL THEN
    RAISE EXCEPTION 'Hostname ''%'' is invalid', v_dc_host.name;
  END IF;

  -- Check if there are addrs or not
  v_host_addrs := get_order_host_addrs(v_dc_host.host_id);
  v_host_addrs_empty := array_length(v_host_addrs, 1) = 1 AND v_host_addrs[1] IS NULL;

  -- Host parent domain
  v_host_parent_domain := get_host_parent_domain(v_dc_host);

  IF  v_create_domain.accreditation_id = v_host_accreditation.accreditation_id THEN
      -- Host and domain are under same accreditation
      IF is_host_provisioned(v_create_domain.accreditation_id, v_dc_host.name) THEN
          -- host already provisioned complete the plan  
          UPDATE create_domain_plan SET status_id = tc_id_from_name('order_item_plan_status', 'completed') WHERE id = NEW.id;
          RETURN NEW;
      END IF;

      IF v_host_parent_domain.id IS NULL THEN
          -- customer does not own parent domain
          RAISE EXCEPTION 'Host create not allowed';
      ELSIF v_host_addrs_empty THEN
          -- ip addresses are required to provision host under parent tld
          RAISE EXCEPTION 'Missing IP addresses for hostname'; 
      END IF;

      PERFORM provision_host(
          v_create_domain.accreditation_id,
          v_create_domain.tenant_customer_id,
          NEW.id,
          v_create_domain.order_metadata,
          v_dc_host.host_id
      );
  ELSE
      -- Host and domain are under different accreditations (registries)
      IF is_host_provisioned(v_create_domain.accreditation_id, v_dc_host.name) THEN
          -- nothing to do; mark plan as completed
          UPDATE create_domain_plan SET status_id = tc_id_from_name('order_item_plan_status', 'completed') WHERE id = NEW.id;
          RETURN NEW;
      END IF;

      PERFORM provision_host(
          v_create_domain.accreditation_id,
          v_create_domain.tenant_customer_id,
          NEW.id,
          v_create_domain.order_metadata,
          v_dc_host.host_id
      );
  END IF;
  
  RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        DECLARE
            error_message TEXT;
        BEGIN
            -- Capture the error message
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;

            -- Update the plan with the captured error message
            UPDATE create_domain_plan
            SET result_message = error_message,
                status_id = tc_id_from_name('order_item_plan_status', 'failed')
            WHERE id = NEW.id;

            RETURN NEW;
        END;
END;
$$ LANGUAGE plpgsql;
