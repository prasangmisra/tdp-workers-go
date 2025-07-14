DROP TABLE IF EXISTS poll_message_type CASCADE;

CREATE TABLE poll_message_type (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name    		            Text NOT NULL,
  descr      	            Text,
  UNIQUE(name)
);

INSERT INTO poll_message_type (name, descr) VALUES 
  ('transfer', 'Transfer notification'),
  ('renewal', 'Renewal notification'),
  ('pending_action', 'Pending action notification'),
  ('domain_info', 'Domain info notification'),
  ('contact_info', 'Contact info notification'),
  ('host_info', 'Host info notification'),
  ('unspec', 'Unspec notification')
  ON CONFLICT DO NOTHING;


DROP TABLE IF EXISTS poll_message;

CREATE TABLE poll_message (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  accreditation    		    Text NOT NULL,
  epp_message_id      	  Text NOT NULL,
  msg                     TEXT,
  lang                    TEXT,
  type                    UUID not null REFERENCES poll_message_type(id),
  data                    JSONB,
  queue_date              TIMESTAMPTZ,
  created_date            TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(epp_message_id, accreditation)
);
