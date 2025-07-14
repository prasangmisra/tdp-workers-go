
--
-- table: poll_message_type
-- description: this table list the poll messages types
--

CREATE TABLE poll_message_type (
  id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name    		            Text NOT NULL,
  descr      	            Text,
  UNIQUE(name)
);


--
-- table: poll_message_status
-- description: this table stores various statuses of the poll_messages
--

CREATE TABLE poll_message_status (
    id            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name          TEXT NOT NULL,
    descr         TEXT NOT NULL,
    UNIQUE(name)
);


--
-- table: poll_message
-- description: this table list the poll messages
--

CREATE TABLE poll_message (
    id                      UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    accreditation           Text NOT NULL,
    epp_message_id          Text NOT NULL,
    msg                     TEXT,
    lang                    TEXT,
    type_id                 UUID NOT NULL REFERENCES poll_message_type(id),
    status_id               UUID NOT NULL REFERENCES poll_message_status(id)
                            DEFAULT tc_id_from_name('poll_message_status','pending'),
    data                    JSONB,
    queue_date              TIMESTAMPTZ,
    created_date            TIMESTAMPTZ DEFAULT NOW(),
    last_submitted_date     TIMESTAMPTZ,
    UNIQUE(epp_message_id, accreditation)
);

