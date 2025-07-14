-- function: validate_escrow_config()
-- description: this function validates the escrow_config record before inserting or updating it
CREATE OR REPLACE FUNCTION validate_escrow_config() RETURNS TRIGGER AS $$
BEGIN
    -- Validation for deposit method
    IF NOT (NEW.deposit_method IN ('SFTP')) THEN
        RAISE EXCEPTION 'Invalid deposit method. Must be ''SFTP''.';
    END IF;

    -- Validation for encryption method
    IF NOT (NEW.encryption_method IN ('GPG')) THEN
        RAISE EXCEPTION 'Invalid encryption method. Must be ''GPG''.';
    END IF;

    -- Validation for authentication method
    IF NOT (NEW.authentication_method IN ('SSH_KEY', 'PASSWORD')) THEN
        RAISE EXCEPTION 'Invalid authentication method. Must be either ''SSH_KEY'' or ''PASSWORD''.';
    END IF;

    -- Validation for authentication method and associated fields
    IF NEW.authentication_method = 'PASSWORD' AND NEW.username IS NULL THEN
        RAISE EXCEPTION 'For password authentication, username must be provided.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
