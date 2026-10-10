# Security model

devbox puts development databases and services, with dev-grade passwords and
security plugins disabled, on a machine with a public IP. The design assumes
those containers are **not** safe to expose, and keeps them unreachable from
anywhere but your laptop's SSH session.

## Layers

| Layer | What it does | Where |
| --- | --- | --- |
| DigitalOcean Cloud Firewall | Inbound: TCP/22 only, only from `DEVBOX_ALLOWED_CIDRS` (default: your current public IPv4 `/32`). Enforced outside the droplet, so Docker's own iptables rules can't bypass it (they do bypass `ufw`). `0.0.0.0/0` is refused. | `ensure_firewall` in `bin/devbox` |
| Docker daemon `"ip": "127.0.0.1"` | Published ports with no explicit host IP (`"5432:5432"`) bind to loopback on the droplet, not every interface. | `lib/cloud-init.yaml` |
| `DOCKER-USER` drop rule | Drops new inbound connections from `eth0`/`eth1` to any container, even one explicitly published on `0.0.0.0`. Re-applied whenever Docker restarts. | `devbox-docker-guard` in `lib/cloud-init.yaml` |
| Docker API not on the network | No TCP socket; the CLI reaches `/var/run/docker.sock` through SSH (`ssh://devbox`). | Docker context |
| sshd hardening | Public key only, root login off, `AllowUsers <one user>`, local TCP forwarding only (no agent/X11/stream-local/tun forwarding), `MaxAuthTries 3`. | `00-devbox.conf` in `lib/cloud-init.yaml` |
| Dedicated key | `~/.ssh/devbox_ed25519`, used only for this host (`IdentitiesOnly yes`); agent forwarding off. | `devbox init`, generated `ssh_config` |
| Host-key pinning | Separate `known_hosts` under `~/.config/devbox`, keyed by alias (`HostKeyAlias`) so IP changes don't matter. Trust-on-first-use only right after devbox creates a droplet; any later key change is a hard failure. | `write_ssh_config`, `forget_host_key` |
| No DO web console | Droplets are created with `--droplet-agent=false`. Root has DO's injected key but can't log in over SSH. | `cmd_up` |
| Tunnel binds loopback | `-L 127.0.0.1:<port>:…` so forwarded ports aren't reachable from your LAN. | `tunnel_start` |
| Docker repo pinned | Docker's apt signing key is checked against its published fingerprint before the repo is trusted. | `devbox-provision` |
| OS updates | Ubuntu's default `unattended-upgrades` installs security updates daily. | image default |

## What stays local, what goes to the droplet

- **Compose files, `.env` / `env_file`, build contexts** are read by the compose
  CLI on your laptop. Interpolated values do end up in container definitions on
  the droplet, as they would in Docker Desktop.
- **`devbox sync`** copies only the directory you name, and excludes `.git`,
  `.env*`, `*.pem`, `*.key`, SSH keys, and dependency/build directories. Check
  what a directory contains before syncing it, and use `.devboxignore` for
  anything else that shouldn't leave your laptop.
- **cloud-init user-data** contains only your SSH *public* key, the username,
  and your home-directory path. It's readable from the droplet's metadata
  service, so never add secrets to `lib/cloud-init.yaml`.
- **Nothing in this repo is secret.** Per-user state (config, generated SSH
  config, pinned host keys, tunnel socket) lives in `~/.config/devbox` (mode
  700). Never commit it.

## Accepted trade-offs

- **`docker` group = root on the droplet.** Anyone holding the devbox SSH key
  controls the machine. The droplet is single-user and holds only dev data.
  Add a passphrase if you want the key protected at rest:
  `ssh-keygen -p -f ~/.ssh/devbox_ed25519` (macOS Keychain will remember it).
- **Trust on first use.** The first connection to a newly created droplet
  accepts its host key without out-of-band verification. The window is the
  minute or two after creation, against an IP that DO just assigned.
- **Containers can reach the internet and the DO metadata service.** DO
  metadata holds no credentials (unlike cloud IAM roles), and user-data holds
  nothing secret.
- **The cloud firewall follows your IP.** On a new network, SSH is blocked
  until you run `devbox allow-ip` (or `devbox up`). Widen
  `DEVBOX_ALLOWED_CIDRS` deliberately, never to the whole internet.

## Reporting

Open a GitHub issue for anything that isn't sensitive; otherwise contact the
repository owner directly.
