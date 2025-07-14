--
-- function: generate_sku(...) 
-- description: will generate non-human-readable SKU for sku table
-- SKUxxxxxxxxx

CREATE OR REPLACE FUNCTION generate_sku()
RETURNS TEXT AS $$
DECLARE
    random_chars TEXT;
BEGIN
    -- Generate 8 random alphabetic characters
    SELECT string_agg(round(random() * 9)::integer::text, '') 
    INTO random_chars FROM generate_series(1, 8);

    -- Return the default value 'sku' followed by the random characters
    RETURN 'sku' || random_chars;
END;
$$ LANGUAGE plpgsql;