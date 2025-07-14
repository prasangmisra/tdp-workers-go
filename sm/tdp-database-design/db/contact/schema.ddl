--
-- table: contact_type
-- description: this table list the possible types of a contact, initially 'individual' or 'organization'
--

CREATE TABLE contact_type (
  id        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name      TEXT NOT NULL,
  descr     TEXT,
  UNIQUE (name)
);

--
-- table: contact
-- description: Contains the basic not character set dependent attributes of extensible contacts.
--

-- TODO: add a constraint to ensure that no two orgs in the same tenant are created (@Francisco, why this?)
-- TODO: add a constraint to check org_* fields considering contact.type_id
-- TODO: add domain to validate phone and fax
-- TODO: add trigger to match phone and fax with country
CREATE TABLE contact (
  id                        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  type_id                   UUID NOT NULL REFERENCES contact_type, 
  title                     TEXT,
  org_reg                   TEXT,
  org_vat                   TEXT,
  org_duns                  TEXT,
  tenant_customer_id        UUID REFERENCES tenant_customer,
  email                     Mbox,
  phone                     TEXT,
  phone_ext                 TEXT,
  fax                       TEXT,
  fax_ext                   TEXT,
  country                   TEXT NOT NULL REFERENCES country(alpha2), -- TODO: move to contact?
  language                  TEXT REFERENCES language(alpha2),  
  tags                      TEXT[],
  documentation             TEXT[],
  short_id                  TEXT NOT NULL UNIQUE DEFAULT gen_short_id(),
  metadata                  JSONB DEFAULT '{}'::JSONB,
  migration_info            JSONB DEFAULT '{}'
  CONSTRAINT short_id_length_check CHECK (char_length(short_id) >= 3 AND char_length(short_id) <= 16)
) INHERITS (class.audit_trail,class.soft_delete);
  

-- Make tags efficiently searchable.
CREATE INDEX ON contact USING GIN(tags);
CREATE INDEX ON contact USING GIN(metadata);

COMMENT ON TABLE contact IS 'Contains the basic not character set dependent attributes of extensible contacts.';
COMMENT ON COLUMN contact.migration_info IS 'Contains migration information as example - {"data_source": "Enom", "invalid_fields": ["country"], "lost_handle": true, "placeholder": true}';
--
-- table: contact_postal
-- description: Contains the character set dependent attributes of extensible contacts.
--

-- TODO: add a constraint to check org_name fields considering contact.type_id
CREATE TABLE contact_postal (
  id                        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  contact_id                UUID NOT NULL REFERENCES contact,
  is_international          BOOLEAN NOT NULL,
  first_name                TEXT,
  last_name                 TEXT,
  org_name                  TEXT,
  address1                  TEXT NOT NULL,
  address2                  TEXT,
  address3                  TEXT,
  city                      TEXT NOT NULL,
  postal_code               TEXT,
  state                     TEXT,
  UNIQUE(contact_id,is_international),   -- either ASCII or UTF-8
  CHECK (NOT is_international
          OR is_null_or_ascii(first_name) AND
             is_null_or_ascii(last_name) AND
             is_null_or_ascii(org_name) AND
             is_null_or_ascii(address1) AND
             is_null_or_ascii(address2) AND
             is_null_or_ascii(address3) AND
             is_null_or_ascii(city) AND
             is_null_or_ascii(postal_code) AND
             is_null_or_ascii(state))
) INHERITS (class.audit_trail,class.soft_delete);

COMMENT ON TABLE contact_postal IS 'Contains the character set dependent attributes of extensible contacts.';

--
-- table: contact_attribute
-- description: holds additional contact attributes all represented as TEXT
--

CREATE TABLE contact_attribute (
  id                        UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  attribute_id              UUID NOT NULL REFERENCES attribute,
  attribute_type_id         UUID NOT NULL DEFAULT tc_id_from_name('attribute_type','contact')
                            CHECK (attribute_type_id = tc_id_from_name('attribute_type','contact')),
  contact_id                UUID NOT NULL REFERENCES contact,
  value                     TEXT NOT NULL,
  UNIQUE(attribute_id,contact_id), -- make sure an attribute can show up only once per contact
  FOREIGN KEY (attribute_id,attribute_type_id) REFERENCES attribute(id,type_id)
) INHERITS (class.audit_trail,class.soft_delete);

CREATE OR REPLACE FUNCTION filter_contact_attribute_value_tgf() RETURNS TRIGGER AS $$
DECLARE
  _filtered_value TEXT;
  _filter       TEXT;
BEGIN

  SELECT filter INTO _filter FROM attribute WHERE id=NEW.attribute_id;

  IF _filter IS NULL THEN 
    RETURN NEW; 
  END IF;

  -- filter the value
  EXECUTE FORMAT(_filter, NEW.value) INTO _filtered_value;

  IF _filtered_value IS NULL THEN
    RAISE EXCEPTION 'Could not filter attribute_id ''%'', value ''%''', NEW.attribute_id, NEW.value;
  END IF;

  NEW.value = _filtered_value;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER contact_attribute_insert_value_tg BEFORE INSERT ON contact_attribute
  FOR EACH ROW
  EXECUTE FUNCTION filter_contact_attribute_value_tgf();

-- TODO: How to handle already stored contact attributes which are missing from the update. 
CREATE OR REPLACE TRIGGER contact_attribute_update_value_tg BEFORE UPDATE ON contact_attribute
  FOR EACH ROW
  EXECUTE FUNCTION filter_contact_attribute_value_tgf();
