-- type: REGEX
-- description: A regular expression pattern
CREATE DOMAIN REGEX AS TEXT
CHECK (
    -- The inserted regex is always syntactically correct and compiles.
    is_valid_regex(value)
);


-- type: PERCENTAGE
-- description: A percentage value, at most 10 digits with 2 decimal places.
CREATE DOMAIN PERCENTAGE AS NUMERIC(10, 2)
CHECK(
    -- The inserted value is always a percentage. at least 0%.
    is_percentage(value)
);
