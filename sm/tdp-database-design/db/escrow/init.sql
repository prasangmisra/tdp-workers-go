-- Insert initial data into escrow_status
INSERT INTO escrow.escrow_status(name,descr,is_success,is_final)
    VALUES
        ('pending','Newly created escrow record',true,false),
        ('processing','Escrow record is being processed',false,false),
        ('completed','Escrow record was completed',true,true),
        ('failed','Escrow record failed',false,true);

-- Insert initial data into escrow_step
INSERT INTO escrow.escrow_step(name,descr)
    VALUES
        ('consolidation','Consolidating the escrow data; exporting from database'),
        ('hashing','Hashing the escrow data for integrity verification'),
        ('compression','Compressing the escrow data to reduce size'),
        ('encryption','Encrypting the escrow data for security'),
        ('upload','Uploading the escrow data to the designated server');
