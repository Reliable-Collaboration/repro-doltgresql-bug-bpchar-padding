# DoltgreSQL 1.3.1: casting a `character(n)` value to `text` keeps its trailing spaces

On DoltgreSQL 1.3.1, a `character(2)` value that ends in a space keeps the space when it is cast to `text`:
`'[' || 'L '::character(2)::text || ']'` answers `[L ]`, and `'L '::character(2)::text = 'L'` answers `f`.
A CHECK constraint on the cast, `CHECK (c::text IN ('L', 'M', 'H'))`, refuses the value with
`ERROR:  Check constraint "t_check" violated`. PostgreSQL 18.6 removes the trailing space in the cast: it
answers `[L]` and `t`, and inserts the row.

Reported upstream: https://github.com/dolthub/doltgresql/issues/3325

## Reproduce it

You need Docker and a POSIX shell: Linux, macOS, or Windows with WSL. The first run downloads the images.

```sh
git clone https://github.com/Reliable-Collaboration/repro-doltgresql-bug-bpchar-padding.git
cd repro-doltgresql-bug-bpchar-padding
./repro.sh
```

`repro.sh` starts PostgreSQL 18.6 and DoltgreSQL 1.3.1 in throwaway containers, waits until both accept
connections, runs [`repro.sql`](repro.sql) on each with the `psql` client inside its container, prints the
two outputs side by side, and removes the containers. It exits 0 when DoltgreSQL's output is identical to
PostgreSQL's, and 1 when it differs.

To try another DoltgreSQL release, name its image (`POSTGRES_IMAGE` works the same way for PostgreSQL):

```sh
DOLTGRESQL_IMAGE=dolthub/doltgresql:latest ./repro.sh
```

### Without the script

The same steps by hand, from the repository directory:

```sh
docker run -d --name repro-doltgresql-bug-bpchar-padding-postgres -e POSTGRES_PASSWORD=password postgres:18.6-bookworm
docker run -d --name repro-doltgresql-bug-bpchar-padding-doltgresql -e DOLTGRES_PASSWORD=password dolthub/doltgresql:1.3.1
docker cp repro.sql repro-doltgresql-bug-bpchar-padding-postgres:/tmp/repro.sql
docker cp repro.sql repro-doltgresql-bug-bpchar-padding-doltgresql:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-bpchar-padding-postgres psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker exec -t -e PGPASSWORD=password repro-doltgresql-bug-bpchar-padding-doltgresql psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker rm -f repro-doltgresql-bug-bpchar-padding-postgres repro-doltgresql-bug-bpchar-padding-doltgresql
```

If a `docker exec` answers that the connection was refused, that server is still starting: wait a few
seconds and run it again.

## The test

[`repro.sql`](repro.sql):

```sql
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
```

## Expected behavior

The cast removes the trailing space: it answers `[L]`, its length is 1, and it equals `'L'`. The CHECK
constraint accepts the value, and the table holds the row. PostgreSQL's documentation for
[character types](https://www.postgresql.org/docs/18/datatype-character.html) says: "Trailing spaces are
removed when converting a character value to one of the other string types."

This is what PostgreSQL 18.6 answers (excerpts from the output of its `docker exec` command):

```
SELECT '[' || 'L '::character(2)::text || ']' AS as_text,
       length('L '::character(2)::text) AS length,
       'L '::character(2)::text = 'L' AS equals_l;
 as_text | length | equals_l 
---------+--------+----------
 [L]     |      1 | t
(1 row)

INSERT INTO t VALUES ('L ');
INSERT 0 1
SELECT '[' || c::text || ']' AS as_text FROM t;
 as_text 
---------
 [L]
(1 row)
```

## Actual behavior

The cast keeps the trailing space: it answers `[L ]`, its length is 2, and it does not equal `'L'`. The
CHECK constraint refuses the value, and the table stays empty.

This is what DoltgreSQL 1.3.1 answers (excerpts from the output of its `docker exec` command):

```
SELECT '[' || 'L '::character(2)::text || ']' AS as_text,
       length('L '::character(2)::text) AS length,
       'L '::character(2)::text = 'L' AS equals_l;
 as_text | length | equals_l 
---------+--------+----------
 [L ]    |      2 | f
(1 row)

INSERT INTO t VALUES ('L ');
psql:/tmp/repro.sql:12: ERROR:  Check constraint "t_check" violated
SELECT '[' || c::text || ']' AS as_text FROM t;
 as_text 
---------
(0 rows)
```

## Side by side

The full output of `./repro.sh`. The side-by-side view shortens long lines, so DoltgreSQL's error line is
cut here; it is shown in full above.

```
Starting postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af
Starting dolthub/doltgresql:1.3.1@sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851

Left: PostgreSQL. Right: DoltgreSQL. Lines that differ are marked with |.

-- Cast a character(2) value that ends in a space to text.    -- Cast a character(2) value that ends in a space to text.
SELECT '[' || 'L '::character(2)::text || ']' AS as_text,     SELECT '[' || 'L '::character(2)::text || ']' AS as_text,
       length('L '::character(2)::text) AS length,                   length('L '::character(2)::text) AS length,
       'L '::character(2)::text = 'L' AS equals_l;                   'L '::character(2)::text = 'L' AS equals_l;
 as_text | length | equals_l                                   as_text | length | equals_l 
---------+--------+----------                                 ---------+--------+----------
 [L]     |      1 | t                                       |  [L ]    |      2 | f
(1 row)                                                       (1 row)

-- The same cast inside a CHECK constraint.                   -- The same cast inside a CHECK constraint.
CREATE TABLE t (                                              CREATE TABLE t (
    c character(2),                                               c character(2),
    CONSTRAINT t_check CHECK (c::text IN ('L', 'M', 'H'))         CONSTRAINT t_check CHECK (c::text IN ('L', 'M', 'H'))
);                                                            );
CREATE TABLE                                                  CREATE TABLE
INSERT INTO t VALUES ('L ');                                  INSERT INTO t VALUES ('L ');
INSERT 0 1                                                  | psql:/tmp/repro.sql:12: ERROR:  Check constraint "t_check" 
SELECT '[' || c::text || ']' AS as_text FROM t;               SELECT '[' || c::text || ']' AS as_text FROM t;
 as_text                                                       as_text 
---------                                                     ---------
 [L]                                                        | (0 rows)
(1 row)                                                     <


Result: DoltgreSQL's output differs from PostgreSQL's on 3 line(s), marked with |.
```

## Other observations

Each was run on the same two images, with the `psql` client inside each container:

- Casts to `varchar`, `varchar(5)` and `name` keep the space too: `'[' || 'L '::char(2)::varchar || ']'` answers `[L ]` (PostgreSQL `[L]`), and `'L '::char(2)::name = 'L'` answers `f` (PostgreSQL `t`).
- More than one trailing space is kept: `'[' || 'L  '::char(3)::text || ']'` answers `[L  ]` (PostgreSQL `[L]`).
- The implicit cast keeps it too: `'[' || 'L '::char(2) || ']'` answers `[L ]` (PostgreSQL `[L]`), and `upper('L '::char(2)) = 'L'`, `lower('L '::char(2)) = 'l'` and `md5('L '::char(2)) = md5('L')` answer `f` (PostgreSQL `t`).
- Other tests of the cast value fail the same way: `'L '::char(2)::text IN ('L', 'M')`, `'L '::char(2)::text = ANY (ARRAY['L'::text])` and `'L '::char(2)::text LIKE 'L'` answer `f` (PostgreSQL `t`).
- `length('L '::char(2))` and `char_length('L '::char(2))` answer `2` (PostgreSQL `1`), and `concat('[', 'L '::char(2)::text, ']')` answers `[L ]` (PostgreSQL `[L]`).
- A `char(2)` column `c` holding `'L '` behaves like the literal: `WHERE c::text = 'L'`, `WHERE c = x` against a `text` column `x` holding `'L'`, and `WHERE c = v` against a `varchar(2)` column `v` holding `'L'` do not return the row (PostgreSQL returns it).
- `INSERT ... SELECT` of that column into a `text` or a `varchar(5)` column stores the value with its space: it reads back as `[L ]` (PostgreSQL `[L]`).
- `COPY ... FROM STDIN` of the value `L ` into a table with the same CHECK constraint is refused too: `ERROR:  Check constraint "k1_c_check" violated` (PostgreSQL `COPY 1`).
- Same answer on both engines: `concat('[', 'L '::char(2), ']')` without a cast answers `[L ]`, `octet_length('L '::char(2))` answers `2`, `'L '::char(2) LIKE 'L'` answers `f`, and `'L '::varchar(2)::text = 'L'` answers `f`.
- Without the space in the literal, `'[' || 'L'::char(2)::text || ']'` answers `[L]` on both engines, but DoltgreSQL does not pad that value: `octet_length('L'::char(2))` answers `1` (PostgreSQL `2`), so the test spells out the space.
- Without any cast, comparing two `bpchar` values also counts the trailing space: `'L '::bpchar = 'L'::bpchar` answers `f` (PostgreSQL `t`), and `CHECK (c IN ('L', 'M', 'H'))` refuses `'L '` with `ERROR:  Check constraint "k2_c_check" violated` (PostgreSQL inserts it).

## Environment

- DoltgreSQL 1.3.1, the newest release when this was written: image `dolthub/doltgresql:1.3.1`, digest
  `sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851`. Its bundled `psql` is 17.11,
  and `SELECT version()` answers `PostgreSQL 15.5`.
- PostgreSQL 18.6: image `postgres:18.6-bookworm`, digest
  `sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af`, with `psql` 18.6.
- Reproduced on 2026-09-11 (UTC) with Docker 29.7.2 on Ubuntu 26.04.1 LTS under WSL2 (Linux
  6.18.33.2-microsoft-standard-WSL2, x86_64).
