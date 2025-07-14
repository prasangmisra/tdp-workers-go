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

  -- Get value of host_object_supported	flag
  SELECT get_tld_setting(
        p_key=>'tld.order.host_object_supported',
        p_tld_id=>v_create_domain.tld_id
    )
  INTO v_host_object_supported;

  -- Host provisioning will be skipped if the host object is not supported for domain accreditation.
  IF v_host_object_supported IS FALSE THEN
    UPDATE create_domain_plan SET status_id = tc_id_from_name('order_item_plan_status', 'completed') WHERE id = NEW.id;
    RETURN NEW;
  END IF;

  -- Host Accreditation
  v_host_accreditation := get_accreditation_tld_by_name(v_dc_host.name, v_dc_host.tenant_customer_id);

  IF v_host_accreditation IS NULL THEN
    RAISE EXCEPTION 'Hostname ''%'' is invalid', v_dc_host.name;
  END IF;

  -- Check if there are addrs or not
  v_host_addrs := get_order_host_addrs(v_dc_host.host_id);
  v_host_addrs_empty := array_length(v_host_addrs, 1) = 1 AND v_host_addrs[1] IS NULL;

  -- Host parent domain
  v_host_parent_domain := get_host_parent_domain(v_dc_host);

  IF v_create_domain.accreditation_id = v_host_accreditation.accreditation_id THEN
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

    IF v_acc_tld IS NULL THEN
      RAISE EXCEPTION 'unsupported domain name ''%''', NEW.name;
    END IF;

    NEW.accreditation_tld_id = v_acc_tld.accreditation_tld_id;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;


-- function: provision_host_job()
-- description: creates the job to create the host
CREATE OR REPLACE FUNCTION provision_host_job() RETURNS TRIGGER AS $$
DECLARE
  v_host     RECORD;
BEGIN
  SELECT
    NEW.id AS provision_host_id,
    NEW.tenant_customer_id AS tenant_customer_id,
    jsonb_get_host_by_id(oh.id) AS host,
    TO_JSONB(va.*) AS accreditation,
    get_accreditation_tld_by_name(oh.name, oh.tenant_customer_id) AS host_accreditation_tld,
    get_tld_setting(
      p_key=>'tld.order.host_ip_required_non_auth',
      p_tld_name=>tld_part(oh.name),
      p_tenant_id=>va.tenant_id
    )::BOOL AS host_ip_required_non_auth,
    NEW.order_metadata AS metadata
  INTO v_host
  FROM order_host oh
  JOIN v_accreditation va ON va.accreditation_id = NEW.accreditation_id
  WHERE oh.id=NEW.host_id;

  UPDATE provision_host SET job_id=job_submit(
    NEW.tenant_customer_id,
    'provision_host_create',
    NEW.id,
    TO_JSONB(v_host.*)
  ) WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
