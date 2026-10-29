# Lembas

A URL shortener for ByWater Solutions, replacing Polr: sign-in with Google Workspace accounts, a REST API described
by OpenAPI, and pages that need no build step.

## Why

Polr 2.3.0b, which serves `bywater.solutions`, has not been released since 2017. It signs in with a shared password,
records clicks with a read-then-write counter that loses updates, redirects with a 301 that browsers cache (so edits
and clicks are never seen again), and runs on a PHP 7 image of its own. Lembas keeps its short links and its API, and:

- **Signs in with Google** (OpenID Connect, PKCE), for the accounts of `LEMBAS_ALLOWED_DOMAIN` only.
- **Is a REST API first**: `api/lembas.yaml` (OpenAPI 3.0) describes it, Mojolicious::Plugin::OpenAPI validates every
  request and response against it, and the pages are Alpine.js components that call it.
- **Keeps the Polr API**, `/api/v2/action/shorten` and `/api/v2/action/lookup`, for the scripts that use it.
- **Runs in a container**, configured by the environment only, logging to the standard error, with health probes,
  admin commands, a graceful stop, and OpenTelemetry traces and logs.
- **Is fully tested**: 100% of the statements, branches, conditions and subroutines of `lib/` and of the lines,
  branches and functions of `public/js/app.js`, Perl::Critic at severity 3, perltidy and prettier.

## Features

- Short links with a random ending (6 letters and digits by default) or a custom one, case sensitive. Shortening a
  URL again gives the link already made for it.
- A 302 redirect, `no-store`, that records the click: time, referer and user agent, never an IP address.
- A dashboard per user: search, edit the long URL, disable, delete, copy, and the stats of a link (clicks per day and
  top referers over 7, 30 or 90 days or a year).
- API keys per user, labelled, shown once, stored as SHA-256 hashes, revoked at any time.
- An admin page (`LEMBAS_ADMIN_EMAILS`): every user, with their links, enabled or disabled, and every link.
- `script/lembas import_polr`: the users, links, clicks and API keys of Polr, so every short link keeps working.

## Configuration

Only the environment. Every `LEMBAS_*` variable can instead be read from the file named by the same variable with
`_FILE` (a Docker secret). Empty values are unset. Lembas refuses to start with an invalid configuration and says
everything that is wrong.

| Variable | Required | Default | |
|---|---|---|---|
| `LEMBAS_BASE_URL` | yes | | The URL of Lembas, `https://lembas.tools.bywatersolutions.com`: the pages, the API, the sign-in callback |
| `LEMBAS_SHORT_URL` | | `LEMBAS_BASE_URL` | The start of the short links, `https://bywater.solutions` |
| `LEMBAS_DB_URL` | yes | | `mariadb://user@host/database` |
| `LEMBAS_DB_PASSWORD` | | | Its password, kept out of the URL |
| `LEMBAS_SECRETS` | yes | | Signs the session cookies, comma separated: the first signs, all are accepted (rotation). 16 characters at least |
| `LEMBAS_OIDC_CLIENT_ID` | yes | | The Google OAuth client |
| `LEMBAS_OIDC_CLIENT_SECRET` | yes | | Its secret |
| `LEMBAS_OIDC_ISSUER` | | `https://accounts.google.com` | The OpenID Connect provider |
| `LEMBAS_ALLOWED_DOMAIN` | yes | | `bywatersolutions.com`: the Workspace domain allowed to sign in |
| `LEMBAS_ADMIN_EMAILS` | | | The admins, comma or space separated |
| `LEMBAS_ENDING_LENGTH` | | `6` | The length of the random endings, 3 to 32 |
| `LEMBAS_SESSION_DAYS` | | `7` | How long a sign-in lasts |
| `LEMBAS_LOG_LEVEL` | | `info` | `trace`, `debug`, `info`, `warn`, `error` or `fatal` |
| `LEMBAS_SITE_NAME` | | `Lembas` | The name shown on the pages |

### Telemetry

OpenTelemetry is on when `OTEL_EXPORTER_OTLP_ENDPOINT` is set and `OTEL_SDK_DISABLED` is not `true`. Every request
except the probes and the static files gets a server span, named after its route, with its database queries and its
requests to Google as children, and every log line becomes a log record of its trace. Query strings (where the Polr
API carries keys and Google its codes), client addresses and email addresses are never recorded. Every log line on
the standard error ends with its `trace_id` and `span_id`.

The standard variables apply: `OTEL_SERVICE_NAME` (`lembas`), `OTEL_RESOURCE_ATTRIBUTES` (`service.version` is
added), `OTEL_TRACES_SAMPLER`, `OTEL_EXPORTER_OTLP_PROTOCOL` (`http/json`, the image has no protobuf),
`OTEL_EXPORTER_OTLP_HEADERS` or `OTEL_EXPORTER_OTLP_HEADERS_FILE`, `OTEL_BSP_SCHEDULE_DELAY` (milliseconds between
exports, 5000) and `OTEL_BSP_EXPORT_TIMEOUT` (10000).

Each prefork worker starts the SDK on its first request and exports from a child process (the batch processors of
the SDK need an IO::Async loop that never runs under Mojolicious), and what is left is exported when the worker stops.
The image stops with SIGQUIT for that.

## Development

Everything runs in Docker: `make help` lists the targets.

```sh
cp .env.example .env    # a Google OAuth client for http://localhost:8080/auth/callback
make dev                # morbo on http://localhost:8080, with MariaDB
make migrate            # in another terminal, once and after each new migration
make dev-otel           # the same with a collector, and Jaeger on http://localhost:16686
```

### Checks

```sh
make test        # the suite, in the test image, against a MariaDB
make lint        # Perl::Critic and the formatting
make format      # perltidy and prettier, on the files
make coverage    # the suite under Devel::Cover: fails unless lib/ is 100% covered
make all         # lint, test and coverage, what CI runs
make smoke       # the production image, with a MariaDB and a collector of its own
```

`git config core.hooksPath .githooks` checks the formatting before every commit. CONTRIBUTING.md has the rules that
keep the coverage at 100%. The JavaScript is tested by `t/js/*.test.js` with the test runner of Node, from
`t/javascript.t`: no build, no npm dependency.

If `docker compose` says "all predefined address pools have been fully subnetted", Docker has no network left for
the project: `docker network prune` removes the unused ones. `script/smoke` only uses the default network.

## API

`GET /api/v1` is the specification. Send an API key in the `X-Api-Key` header, or the session cookie of a signed-in
user. API keys are made on the dashboard, and cannot make or revoke keys themselves.

```sh
curl -H "X-Api-Key: $KEY" -H 'Content-Type: application/json' \
    -d '{"long_url": "https://bywatersolutions.com/education", "ending": "education"}' \
    https://lembas.tools.bywatersolutions.com/api/v1/links
```

| | |
|---|---|
| `GET /api/v1/me` | The user of the request |
| `GET /api/v1/links?q=&page=&per_page=&all=` | Their links (`all`: everybody's, for admins) |
| `POST /api/v1/links` | Shorten `long_url`, with an `ending` or not: 201 for a new link, 200 for the one already made for this URL |
| `GET`, `PATCH`, `DELETE /api/v1/links/{ending}` | A link; change its `long_url` or `is_disabled` |
| `GET /api/v1/links/{ending}/stats?from=&to=` | Clicks per day and top referers, the last 30 days by default |
| `GET`, `POST /api/v1/api_keys`, `DELETE /api/v1/api_keys/{id}` | The API keys of the user (session only) |
| `GET /api/v1/admin/users`, `PATCH /api/v1/admin/users/{id}` | Every user, enable or disable one (admins) |

The Polr API answers as Polr 2 did: `key` as a parameter, plain text unless `response_type=json`.

```sh
curl "https://bywater.solutions/api/v2/action/shorten?key=$KEY&url=https://bywatersolutions.com/"
curl "https://bywater.solutions/api/v2/action/lookup?key=$KEY&url_ending=3Fz&response_type=json"
```

Secret links (`is_secret`, `url_key`) do not exist in Lembas: such links are public.

## Operations

- `GET /health`: the process answers (the HEALTHCHECK of the image).
- `GET /ready`: the database answers and every migration is applied, else a 503 with the reason (the healthcheck of
  the stack).
- Logs: one line per request (`GET /abc123 302 2.1ms id=...`, the probes at the debug level), on the standard error.
  An `X-Request-ID` from the proxy is kept and sent back.
- `docker stop` sends SIGQUIT: the workers finish their requests, export their telemetry, and stop.
- `script/lembas migrate [--status] [--to N]` and `script/lembas import_polr` are the admin commands.

## Deployment

`deploy/docker-swarm/lembas-stack.yml` is the stack of the prod-bwsdocker01 swarm. `.github/workflows/bws-build.yml`
pushes `quay.io/bywatersolutions/lembas:latest` for every push to main, which the shepherd of the swarm rolls out, and
`:X.Y.Z` for a tag `vX.Y.Z` (`release.yml` then moves the Unreleased entries of CHANGELOG.md under it).

### First deployment

1. The database, next to Polr's on 172.20.24.33:

   ```sql
   CREATE DATABASE lembas CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE USER 'lembas'@'%' IDENTIFIED BY '...';
   GRANT ALL ON lembas.* TO 'lembas'@'%';
   ```

2. A Google OAuth client, "Web application", in the Google Cloud console of bywatersolutions.com, with the redirect
   URI `https://lembas.tools.bywatersolutions.com/auth/callback`. Put its client id in the stack file.

3. The secrets, on a manager of the swarm (`docker secret create NAME -`, the value, then Ctrl-D):
   `lembas_db_password`, `lembas_oidc_client_secret`, and `lembas_secrets` (`openssl rand -hex 32`).

4. Until Polr is switched off, remove `` || Host(`bywater.solutions`) `` from the Traefik rule. Then:

   ```sh
   docker stack deploy -c deploy/docker-swarm/lembas-stack.yml lembas
   docker service scale lembas_migrate=1 && docker service logs -f lembas_migrate
   docker service scale lembas_migrate=0
   ```

   The service of the application becomes ready once the database is migrated.

### Switching from Polr

1. Import, first without writing anything, from a machine that reaches both databases (the swarm node does). The
   password files keep the passwords out of the process list and the shell history:

   ```sh
   docker run --rm -it -v /root/lembas-import:/run/import:ro \
       -e LEMBAS_BASE_URL=https://lembas.tools.bywatersolutions.com -e LEMBAS_SHORT_URL=https://bywater.solutions \
       -e LEMBAS_DB_URL=mariadb://lembas@172.20.24.33/lembas -e LEMBAS_DB_PASSWORD_FILE=/run/import/lembas \
       -e LEMBAS_SECRETS_FILE=/run/import/secrets -e LEMBAS_OIDC_CLIENT_ID=unused -e LEMBAS_OIDC_CLIENT_SECRET=unused \
       -e LEMBAS_ALLOWED_DOMAIN=bywatersolutions.com \
       quay.io/bywatersolutions/lembas:latest \
       script/lembas import_polr --from mariadb://polr@172.20.24.33/polr --password-file /run/import/polr --dry-run
   ```

   It reports the users, the links, the API keys it imports and leaves out, the Polr admins (to add to
   `LEMBAS_ADMIN_EMAILS`), the secret links that become public, the links too long for Lembas, and whether Polr
   compared endings without their case. Run it again without `--dry-run`: it can run several times, what is already
   in Lembas is left alone.

2. Remove `bywater.solutions` from the Traefik rule of the polr stack (tools-swarm `roles/polr`), put it back in
   the rule of lembas, and deploy both. Import once more, for the links made in between.

3. Check a few short links, then remove the polr stack. Its database can stay as long as it is wanted.

### Upgrades with migrations

A version with a new migration is rolled back by the swarm, because `/ready` answers 503 until the migration is
applied. Apply it with the new image, then let the application update:

```sh
docker service scale lembas_migrate=1 && docker service logs -f lembas_migrate
docker service scale lembas_migrate=0
docker service update --force lembas_lembas
```

Migrations add to the schema before a later version removes what is no longer used, so the running version keeps
working while the next one is applied.

### Rotating the session secret

Make a new `lembas_secrets` with the new secret first and the old one second, comma separated (Docker secrets cannot
change: create `lembas_secrets_2` and point the stack at it), deploy, and drop the old one a session lifetime later.

### Telemetry for Elastic

Uncomment the `OTEL_*` lines of the stack: `OTEL_EXPORTER_OTLP_ENDPOINT` is the OTLP endpoint of Elastic (or of a
collector in front of it, which `deploy/otel-collector/config.yaml` can start from), and
`OTEL_EXPORTER_OTLP_HEADERS_FILE` names a secret like `Authorization=ApiKey ...`. If the endpoint only accepts
protobuf, add Google::ProtocolBuffers::Dynamic to the image.

## License

AGPLv3, see LICENSE: a version of Lembas that is changed and offered to users over a network must offer them its source too.
