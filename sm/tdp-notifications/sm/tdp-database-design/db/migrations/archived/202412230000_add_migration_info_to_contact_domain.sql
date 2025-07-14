-- contact--
ALTER TABLE public.contact ADD COLUMN IF NOT EXISTS migration_info JSONB DEFAULT '{}';
COMMENT ON COLUMN contact.metadata IS '';
COMMENT ON COLUMN contact.migration_info IS 'Contains migration information as example - {"data_source": "Enom", "invalid_fields": ["country"], "lost_handle": true, "placeholder": true}';
-- domain--
ALTER TABLE public.domain  ADD COLUMN IF NOT EXISTS migration_info JSONB DEFAULT '{}';
COMMENT ON COLUMN domain.migration_info IS 'Contains migration information as example - {"allowed_nameserver_count_issue": true}';

--order_item_import_domain--
DROP TRIGGER IF EXISTS validate_tld_active_tg    ON  public.order_item_import_domain;
DROP TRIGGER IF EXISTS validate_domain_syntax_tg ON  public.order_item_import_domain;