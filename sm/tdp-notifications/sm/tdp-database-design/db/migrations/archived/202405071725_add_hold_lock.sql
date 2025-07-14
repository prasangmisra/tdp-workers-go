UPDATE lock_type SET descr='Requests to transfer the object MUST be rejected' WHERE name='transfer';

INSERT INTO lock_type (name, descr) VALUES
   ('hold', 'Signify that the object is on hold')
   ON CONFLICT (name) DO NOTHING;
