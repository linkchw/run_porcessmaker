# Rashen ProcessMaker deployment

This repository deploys the customized Rashen Group ProcessMaker application
from a published, immutable Docker image. Application source code and build
tools are not required on the deployment server.

## Current release

- Application image: `linkchw/processmaker:3.8.3-50ee749`
- Image digest: `sha256:758a59baa95a927384fe9baae7622fb3187e3a6026a823c1f8b6b337ff4e4b25`
- Application source commit: `50ee7498aaa65a7dc9f218bbb71e674cd3d5e59f`
- Platform: `linux/amd64`

The image and MySQL image are pinned by digest in `compose.yaml`. Docker will
pull them automatically. The database is not exposed to the host, and named
volumes preserve both the database and ProcessMaker shared state.

> Compatibility notice: this release uses ProcessMaker 3.8.3 with MySQL 5.7.
> MySQL 5.7 is end-of-life, and the application repository currently classifies
> this stack as a compatibility deployment rather than a promoted modern
> production runtime. Use a controlled server, TLS, firewalling, monitoring,
> and tested backups.

## Fresh server: copy and paste

Prerequisites: a Linux x86-64 server, Docker Engine, Docker Compose v2,
OpenSSL, and enough disk space for two persistent volumes.

Obtain this deployment repository on the server, then run:

```bash
cd processmaker_deployment
cp .env.example .env
nano .env
./scripts/generate-secrets.sh
docker compose config --quiet
docker compose pull
docker compose up -d --wait
docker compose ps
docker compose logs --no-log-prefix initialize
```

For direct testing by server IP, set these values in `.env` before starting:

```dotenv
APP_BIND_IP=0.0.0.0
APP_PORT=8080
PM_PUBLIC_HOST=YOUR_SERVER_IP
PM_PUBLIC_PORT=8080
```

Then allow TCP port 8080 in the server firewall and open:

```text
http://YOUR_SERVER_IP:8080/
```

For an internet-facing deployment, keep `APP_BIND_IP=127.0.0.1` and place
Nginx, Caddy, or another reverse proxy on the host in front of
`http://127.0.0.1:8080`. Set `PM_PUBLIC_HOST` to the public domain and
`PM_PUBLIC_PORT=443`. The reverse proxy must provide HTTPS.

The administrator username defaults to the `PM_ADMIN_USER` value in `.env`.
Read the generated password locally on the server with:

```bash
sudo cat secrets/admin_password.txt
```

Do not commit, email, or paste either file under `secrets/`. Changing the
admin secret after first initialization does not reset an existing user's
password.

## Verification and routine operation

```bash
docker compose ps
curl --fail --show-error --silent http://127.0.0.1:8080/ >/dev/null
docker compose logs --tail=100 app
docker compose logs --tail=100 initialize
```

The initializer is deliberately idempotent. This command must validate the
existing installation without recreating or deleting it:

```bash
docker compose run --rm initialize
```

Common lifecycle commands:

```bash
docker compose stop
docker compose start
docker compose restart app
docker compose up -d --wait
```

Do not run `docker compose down -v`; the `-v` option deletes the persistent
database and shared-state volumes.

## Back up one consistent release point

The database dump and shared-state archive must always be kept together. The
commands below assume the default database name from `.env`.

```bash
backup_dir="backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir"
docker compose stop app
docker compose exec -T db sh -c 'exec mysqldump -uroot --password="$(cat /run/secrets/db_root_password)" --single-transaction --routines --triggers --events "$PM_DB_NAME"' >"$backup_dir/database.sql"
docker compose run --rm --no-deps --entrypoint sh app -c 'tar -C /opt/processmaker/shared -czf - .' >"$backup_dir/shared-state.tar.gz"
cp compose.yaml public/source-release.json "$backup_dir/"
sha256sum "$backup_dir"/* >"$backup_dir/SHA256SUMS"
docker compose start app
```

Encrypt the backup, copy it off the server, and test restoration regularly.
Never commit backup files to this repository.

## Restore into a separate deployment

Restore into a new Compose project first. Never test a restore over the only
production copy.

1. Copy this repository and the matching backup to another server or folder.
2. Set a new `COMPOSE_PROJECT_NAME` in `.env`.
3. Generate new local Docker/MySQL secrets.
4. Start only the empty database.
5. Restore both artifacts before running the initializer.

```bash
docker compose up -d --wait db
docker compose exec -T db sh -c 'exec mysql -uroot --password="$(cat /run/secrets/db_root_password)" "$PM_DB_NAME"' <BACKUP_DIRECTORY/database.sql
docker compose run --rm --no-deps --entrypoint sh app -c 'tar -C /opt/processmaker/shared -xzf -' <BACKUP_DIRECTORY/shared-state.tar.gz
docker compose run --rm initialize
docker compose up -d --no-deps --wait app
```

Verify login, representative cases, uploads/downloads, Farsi/RTL forms, and
scheduler behavior before treating a restored deployment as usable.

## Upgrade to a newly published application image

Every application release must also update this deployment repository:

1. Replace the application tag and digest in `compose.yaml`.
2. Update the release values and exact source URL in
   `public/source-release.json`.
3. Update the **Current release** section above.
4. Validate the Compose model and test a fresh deployment plus an upgrade.
5. Commit and publish this deployment repository separately.

On a server, first make a matching backup. Then pull and apply the reviewed
deployment-repository commit:

```bash
git pull --ff-only
docker compose config --quiet
docker compose pull app initialize
docker compose run --rm initialize
docker compose up -d --no-deps --force-recreate --wait app
docker compose ps
```

Do not point an older image at a newer database to roll back. Restore the prior
database and shared-state backup together with the prior `compose.yaml`.

## Source and licensing

The application is distributed under AGPL-3.0-only. The Compose file mounts
`public/source-release.json` into the application so the login footer's
“Corresponding Source” page identifies the exact source commit and archive for
the deployed image. Keep that file synchronized with every image release.
