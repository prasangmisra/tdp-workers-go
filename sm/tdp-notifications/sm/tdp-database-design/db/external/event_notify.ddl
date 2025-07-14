-- from the wg-messages repo

CREATE OR REPLACE FUNCTION notify_event(_channel TEXT,_msg_type TEXT,_payload TEXT) RETURNS BOOLEAN AS 
$$
DECLARE 
    part        INT;
    total       INT;
    size        INT;
    chunk_size  INT DEFAULT (8000-10); 
    envelope    TEXT;
    msg         TEXT;
BEGIN


    envelope := JSONB_BUILD_OBJECT(
        'payload',_payload,
        'type',_msg_type,
        'id', gen_random_uuid()
    )::TEXT;

    size := LENGTH(envelope);
    total := CEIL(size::NUMERIC / chunk_size::NUMERIC)::INT;

    FOR part IN SELECT generate_series FROM generate_series(1,total,1)
    LOOP 
        msg := SUBSTRING(envelope,(chunk_size * (part - 1)) + 1 ,chunk_size );
        PERFORM PG_NOTIFY(_channel,FORMAT('%s:%s:%s',part,total,msg));
    END LOOP;

    RETURN TRUE;
END
$$ LANGUAGE PLPGSQL;

COMMENT ON FUNCTION notify_event IS 
'This function is used to send an asynchronous notification to the messaging bus.
It is used in combination with a microservice that uses the postgres asynchronous
notification service to encode the payload into a message that can be consumed 
by other services.

Since the PG_NOTIFY() function is limited to a maximum of 8000 bytes per message,
and considering that some messages may be larger than that, this function will 
split the payload in chunks and sent in a frame-like approach to ensure that the
listener can re-assemble the payload.
';


CREATE OR REPLACE FUNCTION table_event_notify() RETURNS TRIGGER AS
$$
DECLARE
    _payload JSONB;
    _table TEXT;
    _options JSONB DEFAULT '{}'::JSONB;
    _exclude TEXT;
    _new JSONB;
    _old JSONB;
BEGIN

  IF TG_NARGS > 0  THEN
    _table := LOWER(TG_ARGV[0]);


    -- the second argument is options to control
    -- the notify
    IF TG_NARGS > 1 THEN
      _options := TG_ARGV[1]::JSONB;
    END IF;


  ELSE
    _table := LOWER(TG_RELNAME);
  END IF;

  _payload := JSONB_BUILD_OBJECT(
    'TG_NAME',TG_NAME,
    'TG_WHEN',TG_WHEN,
    'TG_LEVEL',TG_LEVEL,
    'TG_OP',TG_OP,
    'TG_RELID',TG_RELID,
    'TG_RELNAME',TG_RELNAME,
    'TG_TABLE_SCHEMA',TG_TABLE_SCHEMA,
    'TG_NARGS',TG_NARGS,
    'TG_ARGV',TO_JSONB(TG_ARGV)
  );


  -- store the NEW and OLD records into a JSONB
  _new := TO_JSONB(NEW.*);
  _old := TO_JSONB(OLD.*);


  -- this is an option to remove the column from the notify.
  -- useful when NOTIFYing about BYTEA columns
  IF _options ? 'exclude' THEN

    FOR _exclude IN SELECT * FROM JSONB_ARRAY_ELEMENTS_TEXT(_options #> '{exclude}')
    LOOP
      _new = _new - _exclude;
      _old = _old - _exclude;
    END LOOP;
  END IF;

  _payload = _payload || JSONB_BUILD_OBJECT('NEW',_new);
  _payload = _payload || JSONB_BUILD_OBJECT('OLD',_old);

  PERFORM notify_event(_table || '_event','table_event_notify',_payload::TEXT);

  RETURN NEW;
END;
$$
LANGUAGE plpgsql;

COMMENT ON FUNCTION table_event_notify IS 
'This trigger is used to generate asynchronous notifications when a table is changed';