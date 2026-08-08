# Rashen ProcessMaker deployment

This repository deploys the customized Rashen Group ProcessMaker application
from a published, immutable Docker image. Application source code and build
tools are not required on the deployment server.

## Current release

- Application image: `linkchw/processmaker:3.8.3-29524e1`
- Image digest: `sha256:6b57dd16521ebee84f14db4658c645d6b0bc5a01b28033f398002d515a5738ee`
- Application source commit: `29524e1`
- Platform: `linux/amd64`

The image and MySQL image are pinned by digest in `compose.yaml`. Docker will
pull them automatically. MySQL binds to host loopback by default, and named
volumes preserve both the database and ProcessMaker shared state.

> Compatibility notice: this release uses ProcessMaker 3.8.3 with MySQL 5.7.
> MySQL 5.7 is end-of-life, and the application repository currently classifies
> this stack as a compatibility deployment rather than a promoted modern
> production runtime. Use a controlled server, TLS, firewalling, monitoring,
> and tested backups.

## Windows Server with WSL 2

Docker Desktop is not supported on Windows Server. This deployment can instead
run with Docker Engine inside an Ubuntu WSL 2 distribution. A native Linux VPS
is simpler and is recommended for a long-running production installation, but
WSL 2 is suitable when the VPS must remain on Windows Server.

Before starting, confirm all of the following:

- The VPS is x86-64/AMD64.
- The VPS provider exposes nested virtualization to the Windows guest. WSL 2
  and Linux containers cannot run without it.
- Windows Server 2022 or 2025 is installed. Windows Server 2019 requires the
  [manual Microsoft WSL installation procedure](https://learn.microsoft.com/en-us/windows/wsl/install-on-server#install-wsl-on-previous-versions-of-windows-server-and-server-core).
- TCP port 8080 can be allowed in both Windows Defender Firewall and any
  firewall/security group provided by the VPS company.

Docker's documentation confirms that
[Docker Desktop is unsupported on Windows Server](https://docs.docker.com/desktop/setup/install/windows-install/).

### Install WSL 2 and Ubuntu

Open **PowerShell as Administrator** and run:

```powershell
wsl.exe --install -d Ubuntu
Restart-Computer
```

After the server restarts, open Ubuntu once to finish creating its Linux user,
then verify that the distribution uses WSL 2:

```powershell
wsl.exe --list --verbose
```

The `VERSION` column for Ubuntu must be `2`. If it is not, run:

```powershell
wsl.exe --set-version Ubuntu 2
```

If WSL reports that virtualization is unavailable, it must be enabled by the
VPS provider; installing more Windows features will not bypass that limitation.

### Install Docker Engine inside Ubuntu

Enter Ubuntu from PowerShell:

```powershell
wsl.exe -d Ubuntu
```

Run the following commands in the Ubuntu shell. These configure Docker's
official apt repository and install Docker Engine with the Compose v2 plugin:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl openssl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run --rm hello-world
sudo docker compose version
```

The current official instructions are maintained in
[Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/).
Use `sudo docker ...` for the deployment commands, or follow Docker's Linux
post-installation instructions to grant a trusted user access to the Docker
socket.

### Deploy from inside Ubuntu

Store this repository in Ubuntu's Linux filesystem, for example under
`~/processmaker_deployment`, rather than under `/mnt/c`. In `.env`, use:

```dotenv
APP_BIND_IP=0.0.0.0
APP_PORT=8080
PM_PUBLIC_HOST=YOUR_WINDOWS_SERVER_PUBLIC_IP
PM_PUBLIC_PORT=8080
PM_PUBLIC_SCHEME=http
```

Then run the commands in [Fresh server: copy and paste](#fresh-server-copy-and-paste)
inside Ubuntu, adding `sudo` before each `docker` command if the Linux user has
not been added to the Docker group.

Confirm the application responds inside WSL before configuring Windows:

```bash
curl --fail --show-error --silent http://127.0.0.1:8080/ >/dev/null
sudo docker compose ps
```

### Forward Windows port 8080 to WSL 2

WSL 2 normally has a private, dynamically assigned IP address. Windows can
usually reach the application through `localhost`, but other computers cannot
reach it through the Windows server IP without Windows-side forwarding. In
**PowerShell as Administrator**, run:

```powershell
$wslIp = ((wsl.exe -d Ubuntu hostname -I) -split '\s+')[0]

netsh interface portproxy delete v4tov4 `
  listenaddress=0.0.0.0 listenport=8080 | Out-Null

netsh interface portproxy add v4tov4 `
  listenaddress=0.0.0.0 listenport=8080 `
  connectaddress=$wslIp connectport=8080

if (-not (Get-NetFirewallRule `
    -DisplayName "Rashen ProcessMaker 8080" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule `
    -DisplayName "Rashen ProcessMaker 8080" `
    -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8080
}
```

Also allow inbound TCP port 8080 in the VPS provider's external firewall or
security group. Verify the forwarding rule with:

```powershell
netsh interface portproxy show v4tov4
Test-NetConnection -ComputerName 127.0.0.1 -Port 8080
```

The site should then be available at:

```text
http://YOUR_WINDOWS_SERVER_PUBLIC_IP:8080/
```

Microsoft documents this NAT behavior and `portproxy` approach in
[Accessing network applications with WSL](https://learn.microsoft.com/en-us/windows/wsl/networking#accessing-a-wsl-2-distribution-from-your-local-area-network-lan).

The WSL IP address can change after `wsl.exe --shutdown` or a Windows restart.
If access stops working, repeat the PowerShell forwarding commands so
`connectaddress` contains the new WSL IP. Also remember that a WSL distribution
does not necessarily start until its owning Windows user launches it. For
unattended recovery after a Windows reboot, configure a Task Scheduler task
under the Windows account that owns the Ubuntu distribution, or start Ubuntu
and run `docker compose up -d` manually.

Direct HTTP access on port 8080 is intended for initial testing. For an
internet-facing production deployment, use a domain, HTTPS, and a reverse
proxy, and forward ports 80/443 as required instead of exposing the application
over plain HTTP.

## Fresh server: copy and paste

Prerequisites: a Linux x86-64 server or Ubuntu under WSL 2, Docker Engine,
Docker Compose v2, OpenSSL, and enough disk space for two persistent volumes.

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
docker compose logs --tail=100 worker
docker compose logs --tail=100 scheduler
```

`app`, `worker`, `scheduler`, and `db` must remain running. ProcessMaker queues
case routing after a Dynaform submission; `worker` consumes that job and
creates the next delegation and assignee. If the worker is stopped, the current
task can close while the case appears to have no next owner. The singleton
`scheduler` runs timers, scheduled cases, message events, notifications, and
recurring maintenance every minute. Never scale `scheduler` above one replica.

Check it at any time:

```bash
docker compose ps app worker scheduler db
docker compose logs --tail=100 worker
docker compose logs --tail=100 scheduler
```

After first adding this worker, it will consume any existing pending routing
jobs. Back up the database first, then watch the worker log and confirm the
affected cases receive their next delegation. Do not delete rows from
`jobs_pending` manually.

For direct testing by server IP, set these values in `.env` before starting:

```dotenv
APP_BIND_IP=0.0.0.0
APP_PORT=8080
PM_PUBLIC_HOST=YOUR_SERVER_IP
PM_PUBLIC_PORT=8080
PM_PUBLIC_SCHEME=http
```

Then allow TCP port 8080 in the server firewall and open:

```text
http://YOUR_SERVER_IP:8080/
```

For an internet-facing deployment, keep `APP_BIND_IP=127.0.0.1` and place
Nginx, Caddy, or another reverse proxy on the host in front of
`http://127.0.0.1:8080`. Set `PM_PUBLIC_HOST` to the public domain,
`PM_PUBLIC_PORT=443`, and `PM_PUBLIC_SCHEME=https`. The reverse proxy must
provide HTTPS.

The administrator username defaults to the `PM_ADMIN_USER` value in `.env`.
Read the generated password locally on the server with:

```bash
sudo cat secrets/admin_password.txt
```

Do not commit, email, or paste either file under `secrets/`. Changing the
admin secret after first initialization does not reset an existing user's
password.

## Public images for Dynaform HTML panels

The `PUBLIC_ASSETS_PATH` directory is mounted read-only in the application and
served anonymously at `/user-assets/`. It accepts PNG, JPG/JPEG, GIF, WebP,
AVIF, and ICO files only; directory listings and active content are denied.
Keep only non-sensitive presentation images here.

With the default `.env` value, add an image on the server with:

```bash
install -d -m 0755 public-assets
install -m 0644 /path/to/company-banner.png public-assets/company-banner.png
```

Use a root-relative URL in a Dynaform HTML panel so the same content works with
an IP address, domain, non-default port, or HTTPS:

```html
<img src="/user-assets/company-banner.png" alt="Company banner"
     style="max-width:100%;height:auto;">
```

The absolute form is `https://YOUR_DOMAIN/user-assets/company-banner.png`.

## Settings logo persistence

Logos uploaded through **Admin > Settings > Logo** are different from public
Dynaform images. They remain private to ProcessMaker and are stored in the
existing `shared_state` Docker volume at:

```text
/opt/processmaker/shared/sites/<workspace>/files/logos
```

The application creates this directory with writable `www-data` ownership at
startup. Verify it without changing data:

```bash
docker compose exec app sh -lc \
  'logo_dir="/opt/processmaker/shared/sites/$PM_WORKSPACE/files/logos"; test -d "$logo_dir"; test -w "$logo_dir"; ls -la "$logo_dir"'
```

Upload, select, and delete these logos only through ProcessMaker Settings.
They do not have a `/user-assets/` URL. The shared-state backup described below
already includes the complete logo directory, and replacing or recreating only
the app container does not remove it.

## Jalali dates in SQL

The application initializer installs `pdate_RG(DATETIME)` in `PM_DB_NAME` on
fresh deployments and validates it on upgrades. It returns Latin digits in
`YYYY/MM/DD HH:MM:SS` format. The Gregorian calendar date is converted while
the input clock time is copied unchanged; no timezone conversion is applied.

```sql
SELECT pdate_RG(ASSIGN_DATE) AS ASSIGN_DATE,
       pdate_RG(UPDATE_DATE) AS UPDATE_DATE
FROM fg_vw_Approves;
```

## Optional Navicat database access

MySQL is published on host port 3306 but bound to `127.0.0.1` by default. This
supports a Navicat SSH tunnel without exposing MySQL to the internet. Use these
connection values in Navicat:

```text
MySQL host: 127.0.0.1
MySQL port: 3306
Database: workflow (or PM_DB_NAME from .env)
Username: root
Password: contents of secrets/db_root_password.txt
```

Configure Navicat's SSH tab with the VPS address, SSH port 22, and the VPS SSH
account. No inbound firewall rule for port 3306 is needed in this mode.

If direct public database access is unavoidable, set the following in `.env`:

```dotenv
DB_BIND_IP=0.0.0.0
DB_PORT=3306
```

Then recreate only the database container so Docker applies the published port:

```bash
docker compose up -d --no-deps --force-recreate --wait db
docker compose ps
sudo ss -ltnp | grep ':3306'
```

Before recreating the container, restrict inbound TCP 3306 in the VPS
provider's firewall/security group to the Navicat computer's fixed public
IP using a `/32` source rule. Apply an equivalent host firewall restriction;
never allow TCP 3306 from `0.0.0.0/0` or `Anywhere`. Docker warns that
published container ports can bypass UFW rules, so the provider firewall is
required rather than relying on UFW alone. If the VPS is behind NAT, also
forward public TCP 3306 to the VM's TCP 3306. Prefer the SSH-tunnel mode above
whenever possible.

## Verification and routine operation

```bash
docker compose ps
curl --fail --show-error --silent http://127.0.0.1:8080/ >/dev/null
docker compose logs --tail=100 app
docker compose logs --tail=100 worker
docker compose logs --tail=100 scheduler
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
docker compose restart app worker scheduler
docker compose up -d --wait
```

Do not run `docker compose down -v`; the `-v` option deletes the persistent
database and shared-state volumes.

## Back up one consistent release point

The database dump, shared-state archive (including Settings logos), and
public-assets archive must always
be kept together. The commands below assume the default database name and
public-assets path from `.env`.

```bash
backup_dir="backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir"
docker compose stop app worker scheduler
docker compose exec -T db sh -c 'exec mysqldump -uroot --password="$(cat /run/secrets/db_root_password)" --single-transaction --routines --triggers --events "$PM_DB_NAME"' >"$backup_dir/database.sql"
docker compose run --rm --no-deps --entrypoint sh app -c 'tar -C /opt/processmaker/shared -czf - .' >"$backup_dir/shared-state.tar.gz"
docker compose run --rm --no-deps --entrypoint sh app -c 'tar -C /opt/processmaker/public-assets -czf - .' >"$backup_dir/public-assets.tar.gz"
cp compose.yaml public/source-release.json "$backup_dir/"
sha256sum "$backup_dir"/* >"$backup_dir/SHA256SUMS"
docker compose start app worker scheduler
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
mkdir -p public-assets
tar -C public-assets -xzf BACKUP_DIRECTORY/public-assets.tar.gz
docker compose run --rm initialize
docker compose up -d --no-deps --wait app worker scheduler
```

Verify login, representative cases, uploads/downloads, Farsi/RTL forms, and
scheduler behavior before treating a restored deployment as usable.

## Upgrade to a newly published application image

### Recovering an older deployment with an anonymous application volume

If `initialize` reports `refusing to seed a non-empty, unrecognized application
volume`, the old Compose stack used Docker's anonymous `/opt/processmaker`
volume. Do not run `docker compose down -v`: that can remove the database.
Back up the database first, then copy the old application volume into the new
named volume before starting the updated stack:

```bash
OLD_APP_VOLUME="$(docker inspect rashen-processmaker-app-1 \
  --format '{{range .Mounts}}{{if eq .Destination "/opt/processmaker"}}{{.Name}}{{end}}{{end}}')"
test -n "$OLD_APP_VOLUME" && echo "old app volume: $OLD_APP_VOLUME"
docker volume create rashen-processmaker_app_state
docker run --rm \
  -v "$OLD_APP_VOLUME:/from:ro" \
  -v rashen-processmaker_app_state:/to \
  alpine:3.20 sh -c 'cp -a /from/. /to/'
docker compose down
docker compose up -d --wait
```

The command copies application files only; `db_data` and `shared_state` remain
separate. If the volume name printed is empty, stop and inspect the container
mounts instead of guessing a volume name.

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
docker compose pull app initialize worker scheduler
docker compose run --rm initialize
docker compose up -d --no-deps --force-recreate --wait app worker scheduler
docker compose ps
```

Do not point an older image at a newer database to roll back. Restore the prior
database and shared-state backup together with the prior `compose.yaml`.

## Source and licensing

The application is distributed under AGPL-3.0-only. The Compose file mounts
`public/source-release.json` into the application so the login footer's
“Corresponding Source” page identifies the exact source commit and archive for
the deployed image. Keep that file synchronized with every image release.
