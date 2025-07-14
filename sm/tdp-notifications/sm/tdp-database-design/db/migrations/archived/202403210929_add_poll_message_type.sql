-- Create poll_message_status table

--
-- table: poll_message_status
-- description: this table stores various statuses of the poll_messages
--

CREATE TABLE IF NOT EXISTS poll_message_status (
    id            UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    name          TEXT NOT NULL,
    descr         TEXT NOT NULL,
    UNIQUE(name)
);

-- Poll Message Statuses
INSERT INTO poll_message_status(name,descr) VALUES
    ('pending','Poll message has been created'),
    ('submitted','Poll message has been submitted'),
    ('processed','Poll message has processed successfully'),
    ('failed','Poll message failed')
ON CONFLICT DO NOTHING;


-- Update table
ALTER TABLE IF EXISTS poll_message
ADD COLUMN IF NOT EXISTS
    status_id UUID NOT NULL REFERENCES poll_message_status(id)
    DEFAULT tc_id_from_name('poll_message_status','pending'),
ADD COLUMN IF NOT EXISTS last_submitted_date TIMESTAMPTZ;
