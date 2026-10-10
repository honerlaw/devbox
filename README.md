# devbox

Run your local-development Docker containers (Postgres, OpenSearch, Ollama, …)
on a DigitalOcean droplet instead of your laptop, without changing your
workflow. Your code, editor and app stay local; `docker` and `docker compose`
transparently target the droplet, and the containers' ports show up on
`127.0.0.1` as if they were running locally.

```
 laptop                                              droplet (Ubuntu 24.04)
 ──────                                              ──────────────────────
 docker / docker compose ──── ssh://devbox ────────▶ Docker Engine
 your app → 127.0.0.1:5432 ── SSH tunnel (-L) ─────▶ 127.0.0.1:5432 (postgres container)
                    ▲
       DigitalOcean Cloud Firewall: only TCP/22, only from your IP
```

It uses only standard tooling: a [Docker context](https://docs.docker.com/engine/manage-resources/contexts/)
over SSH, an SSH port-forward, `doctl`, and cloud-init. No agent or daemon is
installed on your laptop.

## Requirements

- macOS or Linux, bash 3.2+
- [`doctl`](https://docs.digitalocean.com/reference/doctl/how-to/install/), authenticated (`doctl auth init`)
- `docker` CLI with the compose plugin (Docker Desktop is fine; it doesn't need to be running)
- `jq`, `ssh`, `rsync`, `curl`, `lsof` (preinstalled on recent macOS)

## Install

```sh
git clone https://github.com/honerlaw/devbox.git
cd devbox
./install.sh                                  # symlinks bin/devbox into ~/.local/bin
devbox init --region nyc3 --size s-4vcpu-8gb  # config, SSH key, ~/.ssh/config Include
devbox up                                     # creates the droplet (this starts billing)
```

`devbox init` makes no billable changes. It writes `~/.config/devbox/config`,
generates `~/.ssh/devbox_ed25519`, uploads its public half to DigitalOcean, and
adds one `Include` line to the top of `~/.ssh/config` (backed up to
`~/.ssh/config.devbox-backup`).

Driving setup with Claude Code? Point it at [`CLAUDE.md`](CLAUDE.md).

## Daily use

```sh
devbox up          # start (or restore from snapshot); switches docker to the devbox
cd ~/code/myapp
devbox compose up -d   # sync this dir to the droplet, then docker compose up
npm run dev            # app talks to 127.0.0.1:5432 etc. through the tunnel
devbox down        # snapshot + delete the droplet when you're done for a while
```

| Command | What it does |
| --- | --- |
| `devbox up` | Creates the droplet (or restores the latest snapshot, or powers it on), refreshes the firewall to your current IP, switches the Docker context, starts the tunnel. Idempotent: re-run it after sleep or a network change. |
| `devbox down` | Stops the tunnel, switches Docker back to your previous context, shuts down, snapshots, then deletes the droplet. Your volumes (database data) live in the snapshot. |
| `devbox destroy [--purge]` | Deletes the droplet **without** a snapshot. `--purge` also deletes snapshots and the firewall. Asks first; `--yes` to skip. |
| `devbox status` | Droplet, cost, snapshots, firewall sources, tunnel, Docker context. |
| `devbox tunnel start\|stop\|restart\|status` | Manage the port forward for `DEVBOX_FORWARD_PORTS`. |
| `devbox sync [dir]` | rsync a directory to the **same absolute path** on the droplet. |
| `devbox compose …` | `devbox sync .` then `docker --context devbox compose …`. `DEVBOX_NO_SYNC=1` skips the sync. |
| `devbox ssh [cmd]` | Shell on the droplet. |
| `devbox allow-ip` | Re-point the firewall at your current public IP (new network, VPN, …). |
| `devbox doctor` | Check local prerequisites. |
| `devbox uninstall` | Remove local setup (context, Include line, `~/.config/devbox`). Cloud resources are untouched. |

### Why sync, and why the same path?

With a remote Docker host, `docker compose` still reads the compose file,
`.env`/`env_file`, and build contexts **locally** and sends them over. Bind
mounts are different: they name a path **on the Docker host**. Compose turns
`./postgres/init.sql` into an absolute path like
`/Users/you/code/myapp/postgres/init.sql`, so devbox mirrors your `$HOME` path
on the droplet and `devbox sync` copies files there. Anything with no bind
mounts (only named volumes) needs no sync at all; `docker compose up` with the
devbox context works directly.

`devbox sync` excludes `.git`, `node_modules`, `.env*`, `*.pem`, `*.key`, SSH
keys and common build/cache directories. Add a `.devboxignore` (rsync exclude
syntax) to a directory to exclude more.

### Ports

`DEVBOX_FORWARD_PORTS` (default `5432 9200 11434`) are forwarded from
`127.0.0.1:<port>` locally to `127.0.0.1:<port>` on the droplet. If a local
process already holds one of them (e.g. a container still running in Docker
Desktop), `devbox tunnel start` names it and stops. Two projects that both
publish `5432` can't run at once, the same as locally.

## Configuration

`~/.config/devbox/config` (template: [`config.example`](config.example)):

| Key | Default | |
| --- | --- | --- |
| `DEVBOX_NAME` | `devbox` | Droplet name, tag, firewall name, SSH alias, Docker context, snapshot prefix |
| `DEVBOX_REGION` | `nyc3` | Pick the region closest to you; every DB query crosses this link |
| `DEVBOX_SIZE` | `s-4vcpu-8gb` | |
| `DEVBOX_IMAGE` | `ubuntu-24-04-x64` | |
| `DEVBOX_USER` | `dev` | |
| `DEVBOX_SSH_KEY` | `~/.ssh/devbox_ed25519` | |
| `DEVBOX_FORWARD_PORTS` | `5432 9200 11434` | |
| `DEVBOX_ALLOWED_CIDRS` | *(your current IP)/32* | `0.0.0.0/0` is refused |
| `DEVBOX_KEEP_SNAPSHOTS` | `1` | |
| `DEVBOX_SWITCH_CONTEXT` | `1` | `0` leaves your active Docker context alone; use `docker --context devbox …` |
| `DEVBOX_DO_CONTEXT` | *(doctl's current)* | Which `doctl auth` context to use |

## Costs

DigitalOcean bills a droplet for every hour it **exists**, powered on or off.
`s-4vcpu-8gb` is $48/mo (~$0.07/hr). `devbox down` replaces the droplet with a
snapshot, billed at $0.06/GB-month for the disk actually used (typically a few
GB, so well under $1/mo). Restoring takes a few minutes.

## Security

See [docs/SECURITY.md](docs/SECURITY.md). In short: SSH is the only way in,
restricted to your IP by a cloud firewall, key-only, one non-root user; the
Docker API is never exposed on the network; container ports bind to loopback
on the droplet and are reachable only through your SSH tunnel.

## Troubleshooting

- **`docker` commands hang or fail after sleep / Wi-Fi change:** `devbox up`
  (refreshes firewall IP, SSH config, tunnel).
- **`Connection timed out` on SSH:** your public IP changed; `devbox allow-ip`.
- **`REMOTE HOST IDENTIFICATION HAS CHANGED`:** devbox only resets the pinned
  host key when it creates a droplet. If you didn't just recreate it, stop and
  investigate. If you did (e.g. outside devbox), remove the entry with
  `ssh-keygen -R devbox -f ~/.config/devbox/known_hosts`.
- **Provisioning didn't finish:** `devbox ssh 'sudo cloud-init status --long; sudo tail -50 /var/log/cloud-init-output.log'`.
- **Bind-mounted file missing in a container:** `devbox sync <dir containing it>`.
- **Back to local Docker for a moment:** `docker --context desktop-linux …`, or `docker context use desktop-linux`.
