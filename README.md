# PgBouncer transaction pooling: "cannot execute INSERT in a read-only transaction"

Reproduces read-only state leaking between clients when HikariCP (Java) goes through
PgBouncer in `pool_mode = transaction`, and proves two PgBouncer-only fixes. No application code changes.

## Root cause

A client sets read-only at session level: explicitly with `SET default_transaction_read_only = on`,
or through pgjdbc `setReadOnly(true)`, for example Spring `@Transactional(readOnly = true)`.
With autocommit, every statement is its own transaction, so PgBouncer can route the
`SET ... on`, the query and the `SET ... off` (or Hikari's reset on `close()`) to different
server backends. A backend left with read-only on is then handed to a writer:

```
ERROR: cannot execute INSERT in a read-only transaction   (SQLSTATE 25006)
```

## Requirements

CentOS Stream, RHEL, Rocky or Alma 8/9 with internet access to download.postgresql.org and
repo1.maven.org. Set `MAVEN_REPO` to use an internal mirror instead.

| Component  | Package                              | Source                   |
|------------|--------------------------------------|--------------------------|
| PostgreSQL | postgresql16-server (14+ required)   | PGDG repo                |
| PgBouncer  | pgbouncer (1.20+ for FIX=track)      | PGDG repo                |
| Java       | java-17-openjdk-devel (JDK, not JRE) | OS repo                  |
| Jars       | HikariCP 5.1.0, pgjdbc 42.7.4, slf4j | Maven Central, auto      |

## Quick start

```bash
chmod +x *.sh
sudo ./install-centos.sh        # or: sudo SKIP_PG=1 ./install-centos.sh if PostgreSQL 14+ already runs
./run-all.sh                    # as a normal user, not root
```

Expected summary:

```
none     RESULT: REPRODUCED - N read-only errors leaked to writers
track    RESULT: no read-only errors
reset    RESULT: no read-only errors
```

## Single scenarios

```bash
./run.sh explicit                # baseline: raw SET like in the DB log
./run.sh jdbc                    # baseline: conn.setReadOnly(true) through Hikari
./run.sh none                    # control: readers never touch read-only, expect 0 errors
FIX=track ./run.sh explicit      # fix A
FIX=reset ./run.sh explicit      # fix B
```

Environment variables: `DB_PORT` (default 5432), `PGB_PORT` (default 6433, avoids clashing
with a system PgBouncer), `MAVEN_REPO`.

## The fixes (pgbouncer.ini)

**Fix A:** needs PgBouncer 1.20+ and PostgreSQL 14+. PgBouncer tracks each client's value
and re-applies it on whichever backend the client gets:

```ini
track_extra_parameters = default_transaction_read_only
```

**Fix B:** works on any version. Adds one round trip per transaction:

```ini
server_reset_query = RESET default_transaction_read_only
server_reset_query_always = 1
```

Avoid `DISCARD ALL` with `server_reset_query_always = 1`. It drops pgjdbc's server-side
prepared statements.

In production, run `RELOAD;` in the PgBouncer admin console after the change, then `RECONNECT;`
(1.21+) or restart PgBouncer, so that already-polluted server connections are dropped.

## Files

| File                | Purpose                                                   |
|---------------------|-----------------------------------------------------------|
| `install-centos.sh` | Installs PostgreSQL, PgBouncer and the JDK; creates the DB |
| `setup.sql`         | Role, database and table (idempotent)                     |
| `pgbouncer.ini`     | Template configuration                                    |
| `userlist.txt`      | PgBouncer auth file (`repro`/`repro`, lab only)           |
| `Repro.java`        | HikariCP load: 4 writers and 2 read-only readers          |
| `run.sh`            | One scenario                                              |
| `run-all.sh`        | Baseline plus both fixes, with a summary                  |

Logs: `/tmp/pgb-repro/pgbouncer.log`, `results/`.
Admin console during a run: `psql -h 127.0.0.1 -p 6433 -U repro pgbouncer`, then `SHOW SERVERS;`
