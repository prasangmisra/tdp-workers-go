-- The FQDN abstraction is used to process fully qualified domain names.

CREATE OR REPLACE FUNCTION ValidFQDN(d TEXT) RETURNS BOOLEAN AS $$
SELECT $1 ~ '^[a-z0-9][-a-z0-9]{0,62}(\.[a-z0-9][-a-z0-9]{0,62})+$'
           AND LENGTH($1) < 255;
$$ LANGUAGE SQL STRICT IMMUTABLE SECURITY DEFINER;

COMMENT ON FUNCTION ValidFQDN ( TEXT ) IS '
Validate that the passed text string resembles a valid fully qualified domain
name. This includes validating that no label is longer than 63 characters and
the total string does not exceed 255 characters. Also, this enforces lower case
folding.

The length restrictions are taken from RFC-1035 § 2.3.4.
';

CREATE DOMAIN fqdn AS TEXT CHECK ( ValidFQDN(value) );

COMMENT ON DOMAIN fqdn IS '
A FQDN represents a valid domain name stored as TEXT. Domain names are
stored with case folded to lowercase.
';

-- The lhs abstraction provides the left hand side of a mailbox.

CREATE OR REPLACE FUNCTION ValidLHS(u TEXT) RETURNS BOOLEAN AS $$
SELECT $1 ~ '^[-_a-z0-9.+^\$]{1,}$'
           AND LENGTH($1) <= 64;
$$ LANGUAGE SQL STRICT IMMUTABLE SECURITY DEFINER;

COMMENT ON FUNCTION ValidLHS(TEXT) IS '
Validate that the passed text string is a valid left hand side for a mailbox.
';

CREATE DOMAIN lhs AS TEXT CHECK ( ValidLHS(value) );

COMMENT ON DOMAIN lhs IS '
The LHS of an email address or mailbox. LHS are stored as lower case strings.
';

-- The Mbox (mailbox) abstraction is used to manipulate the multiple mailboxes
-- that can exist for our users. This is essentially a simplified email address.

CREATE OR REPLACE FUNCTION ValidMbox(u TEXT) RETURNS BOOLEAN AS $$
SELECT $1 ~ '^[-_a-z0-9.+^\$]{1,}@.{1,}$'
           AND public.ValidLHS(split_part($1, '@', 1))
           AND public.ValidFQDN(split_part($1, '@', 2))
           AND split_part($1, '@', 3) = '';
$$ LANGUAGE SQL STRICT IMMUTABLE SECURITY DEFINER;

COMMENT ON FUNCTION ValidMbox ( TEXT ) IS '
Validate that the passed text string is considered a valid email address in our
system. This is, has the form local-part@FQDN.
';

CREATE DOMAIN Mbox AS TEXT CHECK ( ValidMbox(value) );

COMMENT ON DOMAIN Mbox IS '
A Mbox represents a valid mail store encoded as TEXT. In our application,
mailboxes are email addresses with case folded to lowercase.
';

CREATE OR REPLACE FUNCTION get_lhs(u Mbox) RETURNS lhs AS
$$
DECLARE
    part TEXT;
BEGIN
    part = split_part(u, '@', 1);
    RETURN part;
END;
$$
    LANGUAGE plpgsql SECURITY DEFINER IMMUTABLE;

COMMENT ON FUNCTION get_lhs(Mbox) IS '
Return the leftmost part of the mailbox name before the "@". This is commonly
considered the "local-part" of an email address.
';

CREATE OR REPLACE FUNCTION get_rhs(u Mbox) RETURNS fqdn AS
$$
DECLARE
    part TEXT;
BEGIN
    part = split_part(u, '@', 2);
    RETURN part;
END;
$$
    LANGUAGE plpgsql SECURITY DEFINER IMMUTABLE;

COMMENT ON FUNCTION get_rhs(Mbox) IS '
Return the rightmost part of the mailbox name after the "@". This is namely the
FQDN where the email address is routed to.
';