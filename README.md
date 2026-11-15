# paikliin

A URL shortener written in Haskell with Servant, hasql and Postgres.

# Prerequisites

- Docker with the Compose and Buildx plugins

To run the tests, also:

- GHC 9.10.3 and cabal, installed with [GHCup](https://www.haskell.org/ghcup/)
- libpq, the Postgres client library (`libpq-dev` on Debian and Ubuntu, `postgresql-libs` on Arch)

# Run it

```sh
docker compose up --build
```

```sh
curl -X POST localhost:8080/links -H 'Content-Type: application/json' -d '{"url":"https://haskell.org"}'
curl -i localhost:8080/q0U
```

The first link gets the code `q0U`.

To run the tests, with Compose running:

```sh
cp .env.example .env && source .env
docker compose exec db createdb -U postgres paikliin_test
cabal test
```

# API

| Endpoint | Request | Response |
|---|---|---|
| `POST /links` | `POST /links`<br>`Content-Type: application/json`<br><br>`{"url": "https://haskell.org", "ttlSeconds": 60}` | `201 Created`<br>`Content-Type: application/json;charset=utf-8`<br><br>`{"code": "q0U", "target": "https://haskell.org", "createdAt": "2026-11-14T03:17:55Z", "expiresAt": "2026-11-14T03:18:55Z"}` |
| `GET /links/:code` | `GET /links/q0U` | `200 OK`<br>`Content-Type: application/json;charset=utf-8`<br><br>The same JSON as above. |
| `DELETE /links/:code` | `DELETE /links/q0U` | `204 No Content` |
| `GET /:code` | `GET /q0U` | `302 Found`<br>`Location: https://haskell.org` |
| `GET /health` | `GET /health` | `200 OK`<br>`Content-Type: text/plain;charset=utf-8`<br><br>`ok` |

`ttlSeconds` is optional; without it, the link never expires and `expiresAt` is `null`.

Errors: `400 Bad Request` for an invalid URL or TTL, `404 Not Found` for an unknown code, and `410 Gone` for an expired link.

# Design

## Domain model

The core is one pure module, `Domain`, with no IO, so it's tested without a database or a clock.

- **Validated types.** A `LongUrl` or `ShortCode` can only be created by a parsing function, so the rest of the code never handles an invalid one.
- **Time is an argument.** Functions that depend on time take `now` as a parameter instead of reading the clock, and tests pass a fixed date.
- **Short codes are the base62 form of a sequence number.** There's no randomness and no collisions. Tradeoff: codes are guessable (`q0U`, `q0V`, ...), which is fine for public links but not for private ones.

## Storage

- **Plain SQL with hasql.** Each query is a typed SQL statement; there's no ORM.
- **Numbered migrations.** SQL files are applied once, in order, and recorded in a `schema_migrations` table. They run as a separate command, `paikliin migrate`, not at server start, so several servers can start together without racing.
- **Unique index on `code`.** Every redirect looks a link up by its code. With 100,000 rows, the lookup took 0.05 ms with the index and 14.8 ms without it. Tradeoff: every insert also updates the index.
- **Stored data is trusted.** Rows were validated before they were written, so they aren't validated again when read. Tradeoff: stricter validation rules don't apply to rows that already exist.

## HTTP

- **302, not 301.** Browsers cache a 301 permanently, which would break deleting and expiring links.
- **410 for expired links.** It tells "this link existed" apart from "this link never existed" (404).

## Containers

- **Two-stage image.** One stage compiles the code. The final image holds only the binary, its system libraries and the SQL migrations.
- **Dependencies are built before the source is copied in.** Docker reuses that layer, so a code change rebuilds in seconds.
- **Migrations run in a one-off container** that must finish before the server starts.
- **Database files live in a named volume,** so data survives when containers are removed.
