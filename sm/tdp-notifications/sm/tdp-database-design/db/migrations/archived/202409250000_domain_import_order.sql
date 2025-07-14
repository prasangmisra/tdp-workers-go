-- Add new order type for domain import

INSERT INTO public.order_type (product_id,name) SELECT id, 'import' FROM product WHERE name = 'domain'
ON CONFLICT DO NOTHING;

-- table: order_item_import_domain
-- description: this table stores attributes of domain related import order
--
CREATE TABLE IF NOT EXISTS public.order_item_import_domain (
	"name" public."fqdn" NOT NULL,
	registration_period int4 DEFAULT 1 NOT NULL,
	accreditation_tld_id uuid NOT NULL,
	auto_renew bool DEFAULT true NOT NULL,	
	auth_info text NULL,	
	roid text NULL,
	ry_created_date timestamptz NOT NULL,
	ry_expiry_date timestamptz NOT NULL,	
	ry_transfered_date timestamptz NULL,
	deleted_date timestamptz NULL,
	expiry_date timestamptz NOT NULL,	
	tags _text NULL,
	metadata jsonb NULL,
	domain_id uuid NOT NULL,
	CONSTRAINT order_item_import_domain_pkey PRIMARY KEY (id),
	CONSTRAINT order_item_import_domain_accreditation_tld_id_fkey FOREIGN KEY (accreditation_tld_id) REFERENCES public.accreditation_tld(id),
	CONSTRAINT order_item_import_domain_order_id_fkey FOREIGN KEY (order_id) REFERENCES public."order"(id),
	CONSTRAINT order_item_import_domain_status_id_fkey FOREIGN KEY (status_id) REFERENCES public.order_item_status(id)	
)
INHERITS (public.order_item,"class".audit_trail);
CREATE UNIQUE INDEX IF NOT EXISTS order_item_import_domain_name_accreditation_tld_id_idx ON public.order_item_import_domain USING btree (name, accreditation_tld_id);
CREATE INDEX IF NOT EXISTS order_item_import_domain_order_id_idx ON public.order_item_import_domain USING btree (order_id);
CREATE INDEX IF NOT EXISTS order_item_import_domain_status_id_idx ON public.order_item_import_domain USING btree (status_id);

-- prevents order creation if tld is not active
CREATE OR REPLACE  TRIGGER  validate_tld_active_tg BEFORE
INSERT
    ON
    public.order_item_import_domain FOR EACH ROW EXECUTE FUNCTION validate_tld_active();

-- prevent order creation if domain syntax is invalid   
CREATE OR REPLACE TRIGGER  validate_domain_syntax_tg BEFORE
INSERT
    ON
    public.order_item_import_domain FOR EACH ROW EXECUTE FUNCTION validate_domain_syntax();   

\i triggers.ddl