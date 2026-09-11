-- Cast a character(2) value that ends in a space to text.
SELECT '[' || 'L '::character(2)::text || ']' AS as_text,
       length('L '::character(2)::text) AS length,
       'L '::character(2)::text = 'L' AS equals_l;

-- The same cast inside a CHECK constraint.
CREATE TABLE t (
    c character(2),
    CONSTRAINT t_check CHECK (c::text IN ('L', 'M', 'H'))
);

INSERT INTO t VALUES ('L ');

SELECT '[' || c::text || ']' AS as_text FROM t;
