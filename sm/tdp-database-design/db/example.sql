CREATE TABLE customer(
   id       UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
   name     TEXT,
   dob      TIMESTAMPTZ,
   address  TEXT
) inherits(class.audit);

\i post-create.sql

INSERT INTO customer(name,dob,address)
  VALUES
  ('John Doe','1990-03-01','Foo Bar Street'),
  ('Peter Rabbit','1975-12-01','96 Mowat Ave.');

UPDATE customer SET address='950 Charter St.' WHERE name ='John Doe';
