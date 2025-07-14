--
-- table: lock_type
-- description: this table lists all posible lock types which block certain operation
--

CREATE TABLE IF NOT EXISTS lock_type (
  id         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL,
  descr      TEXT NOT NULL,
  UNIQUE (name)
);

INSERT INTO lock_type (name, descr) VALUES
   ('update', 'Requests to update the object MUST be rejected'),
   ('delete', 'Requests to delete the object MUST be rejected'),
   ('transfer', 'Requests to transfer the object MUST be rejected.')
   ON CONFLICT (name) DO NOTHING;

--
-- table: domain_lock
-- description: this table joins domain and lock_type
--

CREATE TABLE IF NOT EXISTS domain_lock
(
    id                  UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    domain_id           UUID NOT NULL REFERENCES domain,
    type_id             UUID NOT NULL REFERENCES lock_type,
    is_internal         BOOLEAN NOT NULL DEFAULT FALSE, -- set by registrar
    created_date        TIMESTAMPTZ DEFAULT NOW(),
    expiry_date         TIMESTAMPTZ,
    UNIQUE(domain_id, type_id, is_internal),
    CHECK( 
      expiry_date IS NULL OR
      ( 
        expiry_date IS NOT NULL  -- expiry date can be set on internal lock only
        AND is_internal
      ) 
    )
); 

CREATE INDEX IF NOT EXISTS domain_lock_domain_id_idx ON domain_lock(domain_id);
CREATE INDEX IF NOT EXISTS domain_lock_type_id_idx ON domain_lock(type_id);


CREATE OR REPLACE VIEW v_domain_lock AS
SELECT
    dl.id,
    dl.domain_id,
    lt.name,
    dl.is_internal,
    dl.created_date,
    dl.expiry_date
FROM domain_lock dl
JOIN lock_type lt ON lt.id = dl.type_id;


--
-- set_domain_lock is used to set lock on domain
--

CREATE OR REPLACE FUNCTION set_domain_lock(
  _domain_id    UUID,
  _lock_type    TEXT,
  _is_internal  BOOLEAN DEFAULT FALSE,
  _expiry_date  TIMESTAMPTZ DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
  _new_lock_id      UUID;
BEGIN

  EXECUTE 'INSERT INTO domain_lock(
    domain_id,
    type_id,
    is_internal,
    expiry_date
  ) VALUES($1,$2,$3,$4) RETURNING id'
  INTO
    _new_lock_id
  USING
    _domain_id,
    tc_id_from_name('lock_type',_lock_type),
    _is_internal,
    _expiry_date;

  RETURN _new_lock_id;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION set_domain_lock IS
'creates new lock given domain_id UUID, lock_type TEXT, is_intrenal BOOLEAN, expiry_date TIMESTAMPTZ';

--
-- remove_domain_lock is used to remove domain lock
--

CREATE OR REPLACE FUNCTION remove_domain_lock(
  _domain_id    UUID,
  _lock_type    TEXT,
  _is_internal  BOOLEAN
) RETURNS BOOLEAN AS $$
BEGIN

  EXECUTE 'DELETE FROM domain_lock WHERE domain_id = $1 AND type_id = $2 AND is_internal = $3'
  USING
    _domain_id,
    tc_id_from_name('lock_type',_lock_type),
    _is_internal;

  RETURN TRUE;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION remove_domain_lock IS
'removes lock given domain_id UUID, lock_type TEXT, is_intrenal BOOLEAN';


-- adding domain id to domain order tables; The column will be set not null in following migration
ALTER TABLE order_item_update_domain ADD COLUMN IF NOT EXISTS domain_id UUID REFERENCES domain;
ALTER TABLE order_item_renew_domain ADD COLUMN IF NOT EXISTS domain_id UUID REFERENCES domain;

ALTER TABLE order_item_create_domain ADD COLUMN IF NOT EXISTS locks JSONB;
ALTER TABLE order_item_update_domain ADD COLUMN IF NOT EXISTS locks JSONB;

-- no longer needed; locks will be checked instead
DROP TRIGGER IF EXISTS validate_domain_delete_order_tg ON order_item_delete_domain;
DROP FUNCTION IF EXISTS validate_domain_delete_order;


DROP TRIGGER IF EXISTS order_prevent_if_domain_does_not_exist_tg ON order_item_redeem_domain;
CREATE OR REPLACE TRIGGER a_order_prevent_if_domain_does_not_exist_tg
    BEFORE INSERT ON order_item_redeem_domain
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_does_not_exist();

DROP TRIGGER IF EXISTS aa_order_prevent_if_domain_does_not_exist_tg ON order_item_delete_domain;
CREATE OR REPLACE TRIGGER a_order_prevent_if_domain_does_not_exist_tg
    BEFORE INSERT ON order_item_delete_domain
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_does_not_exist();

DROP TRIGGER IF EXISTS aa_order_prevent_if_domain_does_not_exist_tg ON order_item_renew_domain;
CREATE OR REPLACE TRIGGER a_order_prevent_if_domain_does_not_exist_tg
    BEFORE INSERT ON order_item_renew_domain
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_does_not_exist();    

DROP TRIGGER IF EXISTS order_prevent_if_domain_does_not_exist_tg ON order_item_update_domain;
CREATE OR REPLACE TRIGGER a_order_prevent_if_domain_does_not_exist_tg
    BEFORE INSERT ON order_item_update_domain
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_does_not_exist();    


-- function: order_prevent_if_domain_operation_prohibited
-- description: checks if domain operation is prohibited

CREATE OR REPLACE FUNCTION order_prevent_if_domain_operation_prohibited() RETURNS TRIGGER AS $$
DECLARE
    v_lock    RECORD;
BEGIN

  SELECT * INTO v_lock
  FROM v_domain_lock vdl
  WHERE vdl.domain_id = NEW.domain_id
    AND vdl.name = TG_ARGV[0]
    AND (vdl.expiry_date IS NULL OR vdl.expiry_date >= NOW())
  ORDER BY vdl.is_internal DESC -- registrar lock takes precedence
  LIMIT 1;

  IF FOUND THEN
    IF v_lock.is_internal THEN
      RAISE EXCEPTION 'Domain ''%'' % prohibited by registrar', NEW.name, TG_ARGV[0];
    END IF;

    -- check if update lock is being removed as part of this update order
    IF TG_ARGV[0] = 'update' THEN
      IF NEW.locks IS NOT NULL AND NEW.locks ? 'update' AND (NEW.locks->>'update')::boolean IS FALSE THEN
        RETURN NEW;
      END IF;
    END IF;

    RAISE EXCEPTION 'Domain ''%'' % prohibited', NEW.name, TG_ARGV[0];

  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER order_prevent_if_domain_update_prohibited_tg
    BEFORE INSERT ON order_item_update_domain
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_operation_prohibited('update');

CREATE OR REPLACE TRIGGER order_prevent_if_domain_delete_prohibited_tg
    BEFORE INSERT ON order_item_delete_domain
    FOR EACH ROW EXECUTE PROCEDURE order_prevent_if_domain_operation_prohibited('delete');


DROP VIEW IF EXISTS v_domain_epp_status;
DROP TABLE IF EXISTS domain_epp_status;
DROP TABLE IF EXISTS epp_status;

CREATE OR REPLACE VIEW v_domain AS
SELECT
  d.*,
  rgp.id AS rgp_status_id,
	rgp.epp_name AS rgp_epp_status,
  lock.names AS locks
FROM domain d
LEFT JOIN LATERAL (
    SELECT
        rs.epp_name,
        drs.id,
        drs.expiry_date
    FROM domain_rgp_status drs
    JOIN rgp_status rs ON rs.id = drs.status_id
    WHERE drs.domain_id = d.id
    ORDER BY created_date DESC
    LIMIT 1
) rgp ON rgp.expiry_date >= NOW()
LEFT JOIN LATERAL (
    SELECT
        ARRAY_AGG(vdl.name) AS names
    FROM v_domain_lock vdl
    WHERE vdl.domain_id = d.id AND NOT vdl.is_internal
) lock ON TRUE;
