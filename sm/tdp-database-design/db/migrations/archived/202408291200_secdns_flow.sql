ALTER TABLE domain
ADD COLUMN secdns_max_sig_life INT;

DROP TRIGGER IF EXISTS create_domain_secdns_check_single_record_type_tg ON create_domain_secdns; 
DROP TRIGGER IF EXISTS domain_secdns_check_single_record_type_tg ON domain_secdns;

CREATE TABLE IF NOT EXISTS secdns_key_data
(
  id          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  flags       INT NOT NULL,
  protocol    INT NOT NULL DEFAULT 3,
  algorithm   INT NOT NULL,
  public_key  TEXT NOT NULL,
  CONSTRAINT flags_ok CHECK (
    -- equivalent to binary literal 0b011111110111111
    (flags & 65471) = 0
  ),
  CONSTRAINT algorithm_ok CHECK (
    algorithm IN (1,2,3,4,5,252,253,254)
  )
);

CREATE TABLE IF NOT EXISTS secdns_ds_data
(
  id           UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  key_tag      INT NOT NULL,
  algorithm    INT NOT NULL,
  digest_type  INT NOT NULL DEFAULT 1,
  digest       TEXT NOT NULL,

  key_data_id UUID REFERENCES secdns_key_data ON DELETE CASCADE,
  CONSTRAINT algorithm_ok CHECK (
    algorithm IN (1,2,3,4,5,252,253,254)
  )
);

CREATE TABLE IF NOT EXISTS domain_secdns
(
  id            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  domain_id     UUID NOT NULL REFERENCES domain ON DELETE CASCADE,
  ds_data_id    UUID REFERENCES secdns_ds_data ON DELETE CASCADE,
  key_data_id   UUID REFERENCES secdns_key_data ON DELETE CASCADE,
  CHECK(
    (key_data_id IS NOT NULL AND ds_data_id IS NULL) OR
    (key_data_id IS NULL AND ds_data_id IS NOT NULL)
  )
);

DROP INDEX IF EXISTS domain_secdns_domain_id_idx;

CREATE INDEX domain_secdns_domain_id_idx ON domain_secdns(domain_id);

-- need to add validate secdns type function first
CREATE OR REPLACE FUNCTION validate_secdns_type() RETURNS TRIGGER AS $$
DECLARE
  result INTEGER;
  domainId UUID;
BEGIN

  EXECUTE format('SELECT ($1).%I', TG_ARGV[1]) INTO domainId USING NEW;

  EXECUTE format('
    SELECT 1 FROM %I  
    WHERE %I = $1 
    AND (($2 IS NOT NULL AND ds_data_id IS NOT NULL)  
        OR ($3 IS NOT NULL AND key_data_id IS NOT NULL))', TG_ARGV[0], TG_ARGV[1]
    ) INTO result USING domainId, NEW.key_data_id, NEW.ds_data_id;

    IF result IS NOT NULL THEN
      RAISE EXCEPTION 'Cannot mix key_data_id and ds_data_id for the same domain';  
    END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;



CREATE TRIGGER domain_secdns_check_single_record_type_tg
    BEFORE INSERT ON domain_secdns
    FOR EACH ROW EXECUTE PROCEDURE validate_secdns_type('domain_secdns', 'domain_id');


ALTER TABLE order_item_create_domain
ADD COLUMN secdns_max_sig_life INT;

CREATE TABLE IF NOT EXISTS order_secdns_key_data(
  PRIMARY KEY(id)
) INHERITS(secdns_key_data);

CREATE TABLE IF NOT EXISTS order_secdns_ds_data(
  PRIMARY KEY(id),
  FOREIGN KEY (key_data_id) REFERENCES order_secdns_key_data
) INHERITS(secdns_ds_data);

CREATE TABLE IF NOT EXISTS create_domain_secdns (
  id                        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  create_domain_id          UUID NOT NULL REFERENCES order_item_create_domain,
  ds_data_id                UUID REFERENCES order_secdns_ds_data,
  key_data_id               UUID REFERENCES order_secdns_key_data,
  CHECK(
    (key_data_id IS NOT NULL AND ds_data_id IS NULL) OR
    (key_data_id IS NULL AND ds_data_id IS NOT NULL)
  )
) INHERITS(class.audit);

DROP INDEX IF EXISTS create_domain_secdns_domain_id_idx;
CREATE INDEX create_domain_secdns_domain_id_idx ON create_domain_secdns(create_domain_id);

CREATE TRIGGER create_domain_secdns_check_single_record_type_tg
  BEFORE INSERT ON create_domain_secdns
  FOR EACH ROW
  EXECUTE PROCEDURE validate_secdns_type('create_domain_secdns', 'create_domain_id');

  -- function: plan_create_domain_provision_domain()
-- description: create a domain based on the plan
CREATE OR REPLACE FUNCTION plan_create_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_create_domain   RECORD;
    v_pd_id           UUID;
    v_parent_id       UUID;
    v_keydata_id      UUID;
    v_dsdata_id       UUID;
    r                 RECORD;
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
            secdns_max_sig_life,
            pw,
            tags,
            metadata,
            order_metadata
        ) VALUES(
            v_create_domain.domain_name,
            v_create_domain.registration_period,
            v_create_domain.accreditation_id,
            v_create_domain.accreditation_tld_id,
            v_create_domain.tenant_customer_id,
            v_create_domain.auto_renew,
            v_create_domain.secdns_max_sig_life,
            COALESCE(v_create_domain.auth_info, TC_GEN_PASSWORD(16)),
            COALESCE(v_create_domain.tags,ARRAY[]::TEXT[]),
            COALESCE(v_create_domain.metadata, '{}'::JSONB),
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

    -- insert secdns
    INSERT INTO provision_domain_secdns(
        provision_domain_id,
        secdns_id
    ) (
        SELECT
            v_pd_id,
            cds.id 
        FROM create_domain_secdns cds
        WHERE cds.create_domain_id = NEW.order_item_id
    );

    UPDATE provision_domain
    SET is_complete = TRUE, order_item_plan_ids = v_order_item_plan_ids, parent_id = v_parent_id
    WHERE id = v_pd_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- function: plan_update_domain_provision_domain()
-- description: update a domain based on the plan
CREATE OR REPLACE FUNCTION plan_update_domain_provision_domain() RETURNS TRIGGER AS $$
DECLARE
    v_update_domain             RECORD;
    v_pd_id                     UUID;
BEGIN
    -- order information
    SELECT * INTO v_update_domain
    FROM v_order_update_domain
    WHERE order_item_id = NEW.order_item_id;
    -- we now signal the provisioning
    WITH pd_ins AS (
        INSERT INTO provision_domain_update(
            domain_id,
            domain_name,
            auth_info,
            hosts,
            accreditation_id,
            accreditation_tld_id,
            tenant_customer_id,
            auto_renew,
            order_metadata,
            order_item_plan_ids,
            locks,
            secdns_max_sig_life
        ) VALUES(
            v_update_domain.domain_id,
            v_update_domain.domain_name,
            v_update_domain.auth_info,
            v_update_domain.hosts,
            v_update_domain.accreditation_id,
            v_update_domain.accreditation_tld_id,
            v_update_domain.tenant_customer_id,
            v_update_domain.auto_renew,
            v_update_domain.order_metadata,
            ARRAY[NEW.id],
            v_update_domain.locks,
            v_update_domain.secdns_max_sig_life
        ) RETURNING id
    )
    SELECT id INTO v_pd_id FROM pd_ins;

    -- insert contacts
    INSERT INTO provision_domain_update_contact(
        provision_domain_update_id,
        contact_id,
        contact_type_id
    )
        (
            SELECT
                v_pd_id,
                order_contact_id,
                domain_contact_type_id
            FROM update_domain_contact
            WHERE update_domain_id = NEW.order_item_id
        );

    -- insert into secdns
    INSERT INTO provision_domain_update_add_secdns (
        provision_domain_update_id,
        secdns_id
    )(
        SELECT
            v_pd_id,
            id
        FROM update_domain_add_secdns
        WHERE update_domain_id = NEW.order_item_id
    );

    INSERT INTO provision_domain_update_rem_secdns (
        provision_domain_update_id,
        secdns_id
    )(
        SELECT
            v_pd_id,
            id
        FROM update_domain_rem_secdns
        WHERE update_domain_id = NEW.order_item_id
    );


    UPDATE provision_domain_update SET is_complete = TRUE WHERE id = v_pd_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: validate_rem_secdns_exists()
-- description: validate that the secdns record we are trying to remove exists
CREATE OR REPLACE FUNCTION validate_rem_secdns_exists() RETURNS TRIGGER AS $$
BEGIN

    IF NEW.ds_data_id IS NOT NULL THEN
        -- we only need to check ds_data table and not child key_data because
        -- ds_data is generated from key_data
        PERFORM 1 FROM secdns_ds_data 
        WHERE id = (
            SELECT ds_data_id 
            FROM domain_secdns ds
                JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
        AND digest = (SELECT digest FROM order_secdns_ds_data WHERE id = NEW.ds_data_id);

        IF NOT FOUND THEN
            RAISE EXCEPTION 'SecDNS DS record to be removed does not exist';
        END IF;

    ELSE
        PERFORM 1 FROM secdns_key_data
        WHERE id = (
            SELECT key_data_id 
            FROM domain_secdns ds
                JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
        AND public_key = (SELECT public_key FROM order_secdns_key_data WHERE id = NEW.key_data_id);

        IF NOT FOUND THEN
            RAISE EXCEPTION 'SecDNS key record to be removed does not exist';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: validate_add_secdns_does_not_exist()
-- description: validate that the secdns record we are trying to add does not exist
CREATE OR REPLACE FUNCTION validate_add_secdns_does_not_exist() RETURNS TRIGGER AS $$
BEGIN

    IF NEW.ds_data_id IS NOT NULL THEN
        -- we only need to check ds_data table and not child key_data because
        -- ds_data is generated from key_data
        PERFORM 1 FROM secdns_ds_data 
        WHERE id = (
            SELECT ds_data_id 
            FROM domain_secdns ds
                JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
        AND digest = (SELECT digest FROM order_secdns_ds_data WHERE id = NEW.ds_data_id);

        IF FOUND THEN
            RAISE EXCEPTION 'SecDNS DS record to be added already exists';
        END IF;

    ELSE
        PERFORM 1 FROM secdns_key_data
        WHERE id = (
            SELECT key_data_id 
            FROM domain_secdns ds
                JOIN order_item_update_domain oiud ON ds.domain_id = oiud.domain_id
            WHERE oiud.id = NEW.update_domain_id)
        AND public_key = (SELECT public_key FROM order_secdns_key_data WHERE id = NEW.key_data_id);

        IF FOUND THEN
            RAISE EXCEPTION 'SecDNS key record to be already exist';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

ALTER TABLE order_item_update_domain
ADD COLUMN secdns_max_sig_life INT;

CREATE TABLE IF NOT EXISTS update_domain_add_secdns (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  update_domain_id        UUID NOT NULL REFERENCES order_item_update_domain,
  ds_data_id              UUID REFERENCES order_secdns_ds_data,
  key_data_id             UUID REFERENCES order_secdns_key_data,
  CHECK(
    (key_data_id IS NOT NULL AND ds_data_id IS NULL) OR
    (key_data_id IS NULL AND ds_data_id IS NOT NULL)
  )
) INHERITS(class.audit);

DROP TRIGGER IF EXISTS update_domain_add_secdns_validate_record_unique_tg ON update_domain_rem_secdns;

CREATE TRIGGER update_domain_add_secdns_validate_record_unique_tg
  BEFORE INSERT ON update_domain_add_secdns
  FOR EACH ROW
  EXECUTE PROCEDURE validate_add_secdns_does_not_exist();

CREATE TABLE IF NOT EXISTS update_domain_rem_secdns (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  update_domain_id        UUID NOT NULL REFERENCES order_item_update_domain,
  ds_data_id              UUID REFERENCES order_secdns_ds_data,
  key_data_id             UUID REFERENCES order_secdns_key_data,
  CHECK(
    (key_data_id IS NOT NULL AND ds_data_id IS NULL) OR
    (key_data_id IS NULL AND ds_data_id IS NOT NULL)
  ) 
) INHERITS(class.audit);

DROP TRIGGER IF EXISTS update_domain_rem_secdns_validate_record_exists_tg ON update_domain_rem_secdns;

CREATE TRIGGER update_domain_rem_secdns_validate_record_exists_tg
  BEFORE INSERT ON update_domain_rem_secdns
  FOR EACH ROW
  EXECUTE PROCEDURE validate_rem_secdns_exists();

  DROP VIEW IF EXISTS v_order_create_domain;
CREATE OR REPLACE VIEW v_order_create_domain AS
SELECT 
  cd.id AS order_item_id,
  cd.order_id AS order_id,
  cd.accreditation_tld_id,
  o.metadata AS order_metadata,
  o.tenant_customer_id,
  o.type_id,
  o.customer_user_id,
  o.status_id,
  s.name AS status_name,
  s.descr AS status_descr,
  tc.tenant_id,
  tc.customer_id,
  tc.tenant_name,
  tc.name,
  at.provider_name,
  at.provider_instance_id,
  at.provider_instance_name,
  at.tld_id AS tld_id,
  at.tld_name AS tld_name,
  at.accreditation_id,
  cd.name AS domain_name,
  cd.registration_period AS registration_period,
  cd.auto_renew,
  cd.locks,
  cd.auth_info,
  cd.secdns_max_sig_life,
  cd.created_date,
  cd.updated_date,
  cd.tags,
  cd.metadata
FROM order_item_create_domain cd
  JOIN "order" o ON o.id=cd.order_id  
  JOIN v_order_type ot ON ot.id = o.type_id
  JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
  JOIN order_status s ON s.id = o.status_id
  JOIN v_accreditation_tld at ON at.accreditation_tld_id = cd.accreditation_tld_id    
;

CREATE OR REPLACE VIEW v_order_update_domain AS
SELECT
    ud.id AS order_item_id,
    ud.order_id AS order_id,
    ud.accreditation_tld_id,
    o.metadata AS order_metadata,
    o.tenant_customer_id,
    o.type_id,
    o.customer_user_id,
    o.status_id,
    s.name AS status_name,
    s.descr AS status_descr,
    tc.tenant_id,
    tc.customer_id,
    tc.tenant_name,
    tc.name,
    at.provider_name,
    at.provider_instance_id,
    at.provider_instance_name,
    at.tld_id AS tld_id,
    at.tld_name AS tld_name,
    at.accreditation_id,
    d.name AS domain_name,
    d.id AS domain_id,
    ud.auth_info,
    ud.hosts,
    ud.auto_renew,
    ud.locks,
    ud.secdns_max_sig_life
FROM order_item_update_domain ud
     JOIN "order" o ON o.id=ud.order_id
     JOIN v_order_type ot ON ot.id = o.type_id
     JOIN v_tenant_customer tc ON tc.id = o.tenant_customer_id
     JOIN order_status s ON s.id = o.status_id
     JOIN v_accreditation_tld at ON at.accreditation_tld_id = ud.accreditation_tld_id
     JOIN domain d ON d.tenant_customer_id=o.tenant_customer_id AND d.name=ud.name
;

ALTER TABLE provision_domain_update
ADD COLUMN secdns_max_sig_life INT;

CREATE TABLE IF NOT EXISTS provision_domain_update_add_secdns (
  id                          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_update_id  UUID NOT NULL REFERENCES provision_domain_update 
                              ON DELETE CASCADE,
  secdns_id                   UUID NOT NULL REFERENCES update_domain_add_secdns
) INHERITS(class.audit_trail);

CREATE TABLE IF NOT EXISTS provision_domain_update_rem_secdns (
  id                          UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_update_id  UUID NOT NULL REFERENCES provision_domain_update 
                              ON DELETE CASCADE,
  secdns_id                   UUID NOT NULL REFERENCES update_domain_rem_secdns
) INHERITS(class.audit_trail);

ALTER TABLE provision_domain
ADD COLUMN secdns_max_sig_life INT;

CREATE TABLE IF NOT EXISTS provision_domain_secdns(
  id                     UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  provision_domain_id    UUID NOT NULL REFERENCES provision_domain 
                         ON DELETE CASCADE,
  secdns_id              UUID NOT NULL REFERENCES create_domain_secdns
) INHERITS(class.audit);

-- function: provision_domain_success()
-- description: complete or continue provision order based on the status
CREATE OR REPLACE FUNCTION provision_domain_success() RETURNS TRIGGER AS $$
DECLARE
    v_domain_secdns_id UUID;
BEGIN
    -- domain
    INSERT INTO domain(
        id,
        tenant_customer_id,
        accreditation_tld_id,
        name,
        auth_info,
        roid,
        ry_created_date,
        ry_expiry_date,
        expiry_date,
        auto_renew,
        secdns_max_sig_life,
        tags,
        metadata
    ) (
        SELECT
            pd.id,    -- domain id
            pd.tenant_customer_id,
            pd.accreditation_tld_id,
            pd.domain_name,
            pd.pw,
            pd.roid,
            COALESCE(pd.ry_created_date,pd.created_date),
            COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%s years',pd.registration_period)::INTERVAL),
            COALESCE(pd.ry_expiry_date,pd.created_date + FORMAT('%s years',pd.registration_period)::INTERVAL),
            pd.auto_renew,
            pd.secdns_max_sig_life,
            pd.tags,
            pd.metadata
        FROM provision_domain pd
        WHERE id = NEW.id
    );
    -- contact association
    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
        SELECT
            pdc.provision_domain_id,
            pdc.contact_id,
            pdc.contact_type_id,
            pc.handle
        FROM provision_domain_contact pdc
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
        WHERE pdc.provision_domain_id = NEW.id
    );
    -- host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            provision_domain_id,
            host_id
        FROM provision_domain_host
        WHERE provision_domain_id = NEW.id
    );
    -- rgp status
    INSERT INTO domain_rgp_status(
        domain_id,
        status_id
    ) VALUES (
        NEW.id,
        tc_id_from_name('rgp_status', 'add_grace_period')
    );


    -- secdns data
    WITH key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM provision_domain_secdns pds 
                JOIN create_domain_secdns cds ON cds.id = pds.secdns_id
                JOIN order_secdns_key_data oskd ON oskd.id = cds.key_data_id
            WHERE pds.provision_domain_id = NEW.id
        ) RETURNING id
    ), ds_key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM provision_domain_secdns pds 
                JOIN create_domain_secdns cds ON cds.id = pds.secdns_id
                JOIN order_secdns_ds_data osdd ON osdd.id = cds.ds_data_id
                JOIN order_secdns_key_data oskd ON oskd.id = osdd.key_data_id
            WHERE pds.provision_domain_id = NEW.id
        ) RETURNING id
    ), ds_data AS (
        INSERT INTO secdns_ds_data
        (
            SELECT 
                osdd.id,
                osdd.key_tag,
                osdd.algorithm,
                osdd.digest_type,
                osdd.digest,
                dkd.id AS key_data_id
            FROM provision_domain_secdns pds 
                JOIN create_domain_secdns cds ON cds.id = pds.secdns_id
                JOIN order_secdns_ds_data osdd ON osdd.id = cds.ds_data_id
                LEFT JOIN ds_key_data dkd ON dkd.id = osdd.key_data_Id
            WHERE pds.provision_domain_id = NEW.id
        ) RETURNING id
    )
    INSERT INTO domain_secdns (
        domain_id,
        ds_data_id,
        key_data_id
    )(
        SELECT NEW.id, NULL, id FROM key_data

        UNION ALL

        SELECT NEW.id, id, NULL FROM ds_data
    );

    -- start the provision domain update
    IF NEW.parent_id IS NOT NULL THEN
        UPDATE provision_domain_update
        SET is_complete = TRUE, domain_id = NEW.id
        WHERE id = NEW.parent_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: provision_domain_update_success()
-- description: provisions the domain once the provision job completes
CREATE OR REPLACE FUNCTION provision_domain_update_success() RETURNS TRIGGER AS $$
DECLARE
    _key   text;
    _value BOOLEAN;
BEGIN
    -- contact association
    INSERT INTO domain_contact(
        domain_id,
        contact_id,
        domain_contact_type_id,
        handle
    ) (
        SELECT
            NEW.domain_id,
            pdc.contact_id,
            pdc.contact_type_id,
            pc.handle
        FROM provision_domain_update_contact pdc
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
        WHERE pdc.provision_domain_update_id = NEW.id
    ) ON CONFLICT (domain_id, domain_contact_type_id)
        DO UPDATE SET contact_id = EXCLUDED.contact_id, handle = EXCLUDED.handle;
    -- insert new host association
    INSERT INTO domain_host(
        domain_id,
        host_id
    ) (
        SELECT
            NEW.domain_id,
            h.id
        FROM ONLY host h
        WHERE h.name IN (SELECT UNNEST(NEW.hosts))
          AND h.tenant_customer_id = NEW.tenant_customer_id
    ) ON CONFLICT (domain_id, host_id) DO NOTHING;
    -- delete removed hosts
    DELETE FROM
        domain_host dh
        USING
            host h
    WHERE
        NEW.hosts IS NOT NULL
      AND h.name NOT IN (SELECT UNNEST(NEW.hosts))
      AND dh.domain_id = NEW.domain_id
      AND dh.host_id = h.id;

    UPDATE domain d
    SET auto_renew = COALESCE(NEW.auto_renew, d.auto_renew),
        auth_info = COALESCE(NEW.auth_info, d.auth_info),
        secdns_max_sig_life = COALESCE(NEW.secdns_max_sig_life, d.secdns_max_sig_life)
    WHERE d.id = NEW.domain_id;

    -- update locks
    IF NEW.locks IS NOT NULL THEN
        FOR _key, _value IN SELECT * FROM jsonb_each_text(NEW.locks)
            LOOP
                IF _value THEN
                    INSERT INTO domain_lock(domain_id,type_id) VALUES
                        (NEW.domain_id,(SELECT id FROM lock_type where name=_key)) ON CONFLICT DO NOTHING ;
                ELSE
                    DELETE FROM domain_lock WHERE domain_id=NEW.domain_id AND
                        type_id=tc_id_from_name('lock_type',_key);
                end if;
            end loop;
    end if;


    -- remove secdns data

    WITH secdns_ds_data_rem AS (
        SELECT 
            secdns.ds_data_id AS id,
            secdns.ds_key_data_id AS key_data_id
        FROM provision_domain_update_rem_secdns pdurs
            JOIN update_domain_rem_secdns udrs ON udrs.id = pdurs.secdns_id
            JOIN order_secdns_ds_data osdd ON osdd.id = udrs.ds_data_id
            LEFT JOIN order_secdns_key_data oskd ON oskd.id = osdd.key_data_id
            -- matching existing ds data (including optional ds key data) on domain
            JOIN LATERAL (
                SELECT
                    ds.domain_id,
                    ds.ds_data_id,
                    sdd.key_data_id AS ds_key_data_id
                FROM domain_secdns ds
                    JOIN secdns_ds_data sdd ON sdd.id = ds.ds_data_id
                    LEFT JOIN secdns_key_data skd ON skd.id = sdd.key_data_id
                WHERE ds.domain_id = NEW.domain_id
                    AND sdd.key_tag = osdd.key_tag
                    AND sdd.algorithm = osdd.algorithm
                    AND sdd.digest_type = osdd.digest_type
                    AND sdd.digest = osdd.digest
                    AND (
                        (sdd.key_data_id IS NULL AND osdd.key_data_id IS NULL)
                        OR
                        (
                            skd.flags = oskd.flags
                            AND skd.protocol = oskd.protocol
                            AND skd.algorithm = oskd.algorithm
                            AND skd.public_key = oskd.public_key
                        )
                    )
            ) secdns ON TRUE
        WHERE pdurs.provision_domain_update_id = NEW.id
    ),
    -- remove ds key data first if exists
    secdns_ds_key_data_rem AS (
        DELETE FROM ONLY secdns_key_data WHERE id IN (
            SELECT key_data_id FROM secdns_ds_data_rem WHERE key_data_id IS NOT NULL
        )
    )
    -- remove ds data if any
    DELETE FROM ONLY secdns_ds_data WHERE id IN (SELECT id FROM secdns_ds_data_rem);

    WITH secdns_key_data_rem AS (
        SELECT 
            secdns.key_data_id AS id
        FROM provision_domain_update_rem_secdns pdurs
            JOIN update_domain_rem_secdns udrs ON udrs.id = pdurs.secdns_id
            JOIN order_secdns_key_data oskd ON oskd.id = udrs.key_data_id
            -- matching existing key data on domain
            JOIN LATERAL (
                SELECT
                    domain_id,
                    key_data_id
                FROM domain_secdns ds
                    JOIN secdns_key_data skd ON skd.id = ds.key_data_id
                WHERE ds.domain_id = NEW.domain_id
                    AND skd.flags = oskd.flags
                    AND skd.protocol = oskd.protocol
                    AND skd.algorithm = oskd.algorithm
                    AND skd.public_key = oskd.public_key
            ) secdns ON TRUE
        WHERE pdurs.provision_domain_update_id = NEW.id
    )
    -- remove key data if any
    DELETE FROM ONLY secdns_key_data WHERE id IN (SELECT id FROM secdns_key_data_rem);

    -- add secdns data

    WITH key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM provision_domain_update_add_secdns pduas
                JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
                JOIN order_secdns_key_data oskd ON oskd.id = udas.key_data_id
            WHERE pduas.provision_domain_update_id = NEW.id
        ) RETURNING id
    ), ds_key_data AS (
        INSERT INTO secdns_key_data
        (
            SELECT 
                oskd.*
            FROM provision_domain_update_add_secdns pduas
                JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
                JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
                JOIN order_secdns_key_data oskd ON oskd.id = osdd.key_data_id
            WHERE pduas.provision_domain_update_id = NEW.id
        ) RETURNING id
    ), ds_data AS (
        INSERT INTO secdns_ds_data
        (
            SELECT 
                osdd.id,
                osdd.key_tag,
                osdd.algorithm,
                osdd.digest_type,
                osdd.digest,
                dkd.id AS key_data_id
            FROM provision_domain_update_add_secdns pduas
                JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
                JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
                LEFT JOIN ds_key_data dkd ON dkd.id = osdd.key_data_Id
            WHERE pduas.provision_domain_update_id = NEW.id
        ) RETURNING id
    )
    INSERT INTO domain_secdns (
        domain_id,
        ds_data_id,
        key_data_id
    )(
        SELECT NEW.domain_id, NULL, id FROM key_data

        UNION ALL

        SELECT NEW.domain_id, id, NULL FROM ds_data
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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
                                 COALESCE(jsonb_agg(ha.address) FILTER (WHERE ha.host_id IS NOT NULL), '[]')
                         ) as data
                  FROM provision_domain pd
                           JOIN provision_domain_host pdh ON pdh.provision_domain_id=pd.id
                           JOIN ONLY host h ON h.id = pdh.host_id
                           -- addresses might be omitted if customer is not authoritative
                           -- or host already existed at registry
                           LEFT JOIN ONLY host_addr ha on ha.host_id = h.id 
                  WHERE pd.id=NEW.id
                  GROUP BY h.name) sub_q
         ),
        price AS (
            SELECT
                JSONB_BUILD_OBJECT(
                        'amount', voip.price,
                        'currency', voip.currency_code,
                        'fraction', voip.currency_fraction
                ) AS data
            FROM v_order_item_price voip
                    JOIN v_order_create_domain vocd ON voip.order_item_id = vocd.order_item_id AND voip.order_id = vocd.order_id
            WHERE vocd.domain_name = NEW.domain_name
            ORDER BY vocd.created_date DESC
            LIMIT 1
        ),
        secdns AS (
            SELECT
                pd.secdns_max_sig_life as max_sig_life,
                JSONB_AGG(
                    JSONB_BUILD_OBJECT(
                        'key_tag', osdd.key_tag,
                        'algorithm', osdd.algorithm,
                        'digest_type', osdd.digest_type,
                        'digest', osdd.digest,
                        'key_data',
                        CASE
                            WHEN osdd.key_data_id IS NOT NULL THEN
                                JSONB_BUILD_OBJECT(
                                    'flags', oskd2.flags,
                                    'protocol', oskd2.protocol,
                                    'algorithm', oskd2.algorithm,
                                    'public_key', oskd2.public_key
                                )
                        END
                    )
                ) FILTER (WHERE cds.ds_data_id IS NOT NULL) AS ds_data,
                JSONB_AGG(
                	JSONB_BUILD_OBJECT(
                    	'flags', oskd1.flags,
                   		'protocol', oskd1.protocol,
                    	'algorithm', oskd1.algorithm,
                    	'public_key', oskd1.public_key
                 	)
            	) FILTER (WHERE cds.key_data_id IS NOT NULL) AS key_data
            FROM provision_domain pd
                JOIN provision_domain_secdns pds ON pds.provision_domain_id = pd.id
                JOIN create_domain_secdns cds ON cds.id = pds.secdns_id
                LEFT JOIN order_secdns_ds_data osdd ON osdd.id = cds.ds_data_id
                LEFT JOIN order_secdns_key_data oskd1 ON oskd1.id = cds.key_data_id
                LEFT JOIN order_secdns_key_data oskd2 ON oskd2.id = osdd.key_data_id
            WHERE pd.id = NEW.id
            GROUP BY pd.id, cds.create_domain_id
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
        TO_JSONB(secdns.*) AS secdns,
        TO_JSONB(a.*) AS accreditation,
        TO_JSONB(vat.*) AS accreditation_tld,
        d.order_metadata AS metadata
    INTO v_domain
    FROM provision_domain d
             JOIN contacts ON TRUE
             JOIN hosts ON TRUE
             LEFT JOIN price ON TRUE
             LEFT JOIN secdns ON TRUE
             JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
             JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
             JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
    WHERE d.id = NEW.id;
    UPDATE provision_domain SET job_id = job_submit(
                v_domain.tenant_customer_id,
                'provision_domain_create',
                NEW.id,
                TO_JSONB(v_domain.*)
                 ) WHERE id=NEW.id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- function: provision_domain_update_job()
-- description: creates the job to update the domain.
CREATE OR REPLACE FUNCTION provision_domain_update_job() RETURNS TRIGGER AS $$
DECLARE
    v_domain     RECORD;
    _parent_job_id      UUID;
    v_locks_required_changes JSONB;
BEGIN
    WITH contacts AS(
        SELECT JSONB_AGG(
            JSONB_BUILD_OBJECT(
                    'type', ct.name,
                    'handle', pc.handle
            )
        ) AS data
        FROM provision_domain_update_contact pdc
                 JOIN domain_contact_type ct ON ct.id =  pdc.contact_type_id
                 JOIN provision_contact pc ON pc.contact_id = pdc.contact_id
                 JOIN provision_status ps ON ps.id = pc.status_id
        WHERE
            ps.is_success AND ps.is_final
            AND pdc.provision_domain_update_id = NEW.id
    ), hosts AS(
        SELECT JSONB_AGG(data) AS data
        FROM(
            SELECT
                JSON_BUILD_OBJECT(
                    'name', h.name,
                    'ip_addresses', JSONB_AGG(ha.address)
                ) AS data
            FROM host h
                        JOIN host_addr ha ON h.id = ha.host_id
            WHERE h.name IN (SELECT UNNEST(NEW.hosts))
            GROUP BY h.name
        ) sub_q
    ), secdns_add AS(
        SELECT
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'key_tag', osdd.key_tag,
                    'algorithm', osdd.algorithm,
                    'digest_type', osdd.digest_type,
                    'digest', osdd.digest,
                    'key_data',
                    CASE
                        WHEN osdd.key_data_id IS NOT NULL THEN
                            JSONB_BUILD_OBJECT(
                                'flags', oskd2.flags,
                                'protocol', oskd2.protocol,
                                'algorithm', oskd2.algorithm,
                                'public_key', oskd2.public_key
                            )
                    END
                )
            ) FILTER (WHERE udas.ds_data_id IS NOT NULL) AS ds_data,
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'flags', oskd1.flags,
                    'protocol', oskd1.protocol,
                    'algorithm', oskd1.algorithm,
                    'public_key', oskd1.public_key
                )
            ) FILTER (WHERE udas.key_data_id IS NOT NULL) AS key_data
        FROM provision_domain_update_add_secdns pduas
            LEFT JOIN update_domain_add_secdns udas ON udas.id = pduas.secdns_id
            LEFT JOIN order_secdns_ds_data osdd ON osdd.id = udas.ds_data_id
            LEFT JOIN order_secdns_key_data oskd1 ON oskd1.id = udas.key_data_id
            LEFT JOIN order_secdns_key_data oskd2 ON oskd2.id = osdd.key_data_id

        WHERE pduas.provision_domain_update_id = NEW.id
        GROUP BY pduas.provision_domain_update_id

    ), secdns_rem AS(
        SELECT
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'key_tag', osdd.key_tag,
                    'algorithm', osdd.algorithm,
                    'digest_type', osdd.digest_type,
                    'digest', osdd.digest,
                    'key_data',
                    CASE
                        WHEN osdd.key_data_id IS NOT NULL THEN
                            JSONB_BUILD_OBJECT(
                                'flags', oskd2.flags,
                                'protocol', oskd2.protocol,
                                'algorithm', oskd2.algorithm,
                                'public_key', oskd2.public_key
                            )
                    END
                )
            ) FILTER (WHERE udrs.ds_data_id IS NOT NULL) AS ds_data,
            JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'flags', oskd1.flags,
                    'protocol', oskd1.protocol,
                    'algorithm', oskd1.algorithm,
                    'public_key', oskd1.public_key
                )
            ) FILTER (WHERE udrs.key_data_id IS NOT NULL) AS key_data
        FROM provision_domain_update_rem_secdns pdurs
            LEFT JOIN update_domain_rem_secdns udrs ON udrs.id = pdurs.secdns_id
            LEFT JOIN order_secdns_ds_data osdd ON osdd.id = udrs.ds_data_id
            LEFT JOIN order_secdns_key_data oskd1 ON oskd1.id = udrs.key_data_id
            LEFT JOIN order_secdns_key_data oskd2 ON oskd2.id = osdd.key_data_id

        WHERE pdurs.provision_domain_update_id = NEW.id
        GROUP BY pdurs.provision_domain_update_id
    )
    SELECT
        NEW.id AS provision_domain_update_id,
        tnc.id AS tenant_customer_id,
        d.order_metadata,
        d.domain_name AS name,
        d.auth_info AS pw,
        contacts.data AS contacts,
        hosts.data as nameservers,
        JSONB_BUILD_OBJECT(
            'max_sig_life', d.secdns_max_sig_life,
            'add', TO_JSONB(secdns_add),
            'rem', TO_JSONB(secdns_rem)
        ) as secdns,
        TO_JSONB(a.*) AS accreditation,
        TO_JSONB(vat.*) AS accreditation_tld,
        d.order_metadata AS metadata,
        va1.value::BOOL AS is_rem_update_lock_with_domain_content_supported,
        va2.value::BOOL AS is_add_update_lock_with_domain_content_supported
    INTO v_domain
    FROM provision_domain_update d
            LEFT JOIN contacts ON TRUE
            LEFT JOIN hosts ON TRUE
            LEFT JOIN secdns_add ON TRUE
            LEFT JOIN secdns_rem ON TRUE
            JOIN v_accreditation a ON a.accreditation_id = NEW.accreditation_id
            JOIN v_accreditation_tld vat ON vat.accreditation_tld_id = d.accreditation_tld_id
            JOIN tenant_customer tnc ON tnc.tenant_id = a.tenant_id
            JOIN v_attribute va1 ON
        va1.tld_id = vat.tld_id AND
        va1.key = 'tld.order.is_rem_update_lock_with_domain_content_supported' AND
        va1.tenant_id = tnc.tenant_id
            JOIN v_attribute va2 ON
        va2.tld_id = vat.tld_id AND
        va2.key = 'tld.order.is_add_update_lock_with_domain_content_supported' AND
        va2.tenant_id = tnc.tenant_id
    WHERE d.id = NEW.id;
    -- Retrieves the required changes for domain locks based on the provided lock configuration.
    SELECT
        JSONB_OBJECT_AGG(
                l.key, l.value::BOOLEAN
        )
    INTO v_locks_required_changes
    FROM JSONB_EACH(NEW.locks) l
             LEFT JOIN v_domain_lock vdl ON vdl.name = l.key AND vdl.domain_id = NEW.domain_id AND NOT vdl.is_internal
    WHERE (NOT l.value::boolean AND vdl.id IS NOT NULL) OR (l.value::BOOLEAN AND vdl.id IS NULL);
    -- If there are required changes for the 'update' lock AND there are other changes to the domain, THEN we MAY need to
    -- create two separate jobs: One job for the 'update' lock and Another job for all other domain changes, Because if
    -- the only change we have is 'update' lock, we can do it in a single job
    IF (v_locks_required_changes ? 'update') AND
       (COALESCE(v_domain.contacts,v_domain.nameservers,v_domain.pw::JSONB)  IS NOT NULL
           OR NOT is_jsonb_empty_or_null(v_locks_required_changes - 'update'))
    THEN
        -- If 'update' lock has false value (remove the lock) and the registry "DOES NOT" support removing that lock with
        -- the other domain changes in a single command, then we need to create two jobs: the first one to remove the
        -- domain lock, and the second one to handle the other domain changes
        IF (v_locks_required_changes->'update')::BOOLEAN IS FALSE AND
           NOT v_domain.is_rem_update_lock_with_domain_content_supported THEN
            -- all the changes without the update lock removal, because first we need to remove the lock on update
            SELECT job_create(
                           v_domain.tenant_customer_id,
                           'provision_domain_update',
                           NEW.id,
                           TO_JSONB(v_domain.*) || jsonb_build_object('locks',v_locks_required_changes - 'update')
                   ) INTO _parent_job_id;
            -- Update provision_domain_update table with parent job id
            UPDATE provision_domain_update SET job_id = _parent_job_id  WHERE id=NEW.id;
            -- first remove the update lock so we can do the other changes
            PERFORM job_submit(
                    v_domain.tenant_customer_id,
                    'provision_domain_update',
                    NULL,
                    jsonb_build_object('locks', jsonb_build_object('update', FALSE),
                                       'name',v_domain.name,
                                       'accreditation',v_domain.accreditation),
                    _parent_job_id
                    );
            RETURN NEW; -- RETURN
        -- Same thing here, if 'update' lock has true value (add the lock) and the registry DOES NOT support adding that
        -- lock with the other domain changes in a single command, then we need to create two jobs: the first one to
        -- handle the other domain changes and the second one to add the domain lock
        elsif (v_locks_required_changes->'update')::BOOLEAN IS TRUE AND
              NOT v_domain.is_add_update_lock_with_domain_content_supported THEN
            -- here we want to add the lock on update (we will do the changes first then add the lock)
            SELECT job_create(
                           v_domain.tenant_customer_id,
                           'provision_domain_update',
                           NEW.id,
                           jsonb_build_object('locks', jsonb_build_object('update', TRUE),
                                              'name',v_domain.name,
                                              'accreditation',v_domain.accreditation)
                   ) INTO _parent_job_id;
            -- Update provision_domain_update table with parent job id
            UPDATE provision_domain_update SET job_id = _parent_job_id  WHERE id=NEW.id;
            -- Submit child job for all the changes other than domain update lock
            PERFORM job_submit(
                    v_domain.tenant_customer_id,
                    'provision_domain_update',
                    NULL,
                    TO_JSONB(v_domain.*) || jsonb_build_object('locks',v_locks_required_changes - 'update'),
                    _parent_job_id
                    );
            RETURN NEW; -- RETURN
        end if;
    end if;
    UPDATE provision_domain_update SET
        job_id = job_submit(
                v_domain.tenant_customer_id,
                'provision_domain_update',
                NEW.id,
                TO_JSONB(v_domain.*) || jsonb_build_object('locks',v_locks_required_changes)
                 ) WHERE id=NEW.id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;