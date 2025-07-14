CREATE TABLE IF NOT EXISTS tld_type (
    id         UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name       TEXT NOT NULL,
    descr       TEXT,
    UNIQUE(name)
) INHERITS (class.audit_trail); 

INSERT into tld_type (name, descr) VALUES
   ('country_code', 'ccTLD'),
   ('generic', 'gTLD')
   ON CONFLICT DO NOTHING; 
  
-- mapping table
CREATE TABLE IF NOT EXISTS tld_type_tld(
    id         		UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    tld_id 			UUID not null REFERENCES tld(id),
    tld_type_id 	UUID not null REFERENCES tld_type(id)
) INHERITS (class.audit_trail);

insert into tld_type_tld 
	(tld_id,  tld_type_id)
    (select id,
		case when LENGTH("name") = 2 
		then tc_id_from_name('tld_type','country_code')
		else tc_id_from_name('tld_type','generic')
		end
    from tld)
    ON CONFLICT DO NOTHING; 
