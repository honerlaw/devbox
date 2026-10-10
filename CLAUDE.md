# devbox: instructions for Claude

`devbox` runs a user's development Docker containers on a DigitalOcean
droplet. `bin/devbox` is one bash script (bash 3.2 compatible, macOS default
shell); `lib/cloud-init.yaml` provisions the droplet. Read `README.md` for
behaviour and `docs/SECURITY.md` before changing anything security-relevant.

## Setting devbox up for a user

Run these in order. Steps 1–4 make no billable changes.

1. **Prerequisites.** `./install.sh`. If it reports missing tools, install them
   (`brew install doctl jq`; Docker Desktop or `brew install docker` for the
   CLI). If `~/.local/bin` isn't on `PATH`, tell the user which profile line
   to add instead of editing their shell profile unasked.
2. **DigitalOcean auth.** `doctl account get`. If it fails, the user must run
   `doctl auth init` themselves (it prompts for a token); suggest they type
   `! doctl auth init`. Never ask for or handle the token yourself. If they
   have several doctl contexts (`doctl auth list`), ask which team to use and
   set `DEVBOX_DO_CONTEXT`.
3. **Choose region and size.** Ask the user which region is nearest to them
   (`doctl compute region list`) and confirm the size (default `s-4vcpu-8gb`,
   $48/mo; `doctl compute size list` for prices). Size it for their compose
   files: OpenSearch/Elasticsearch need about 1.5 GB, a local LLM/embedding
   model in Ollama needs its model size plus about 1 GB.
4. **Init.** `devbox init --region <slug> --size <slug>`, then `devbox doctor`.
5. **Confirm, then `devbox up`.** This creates a billable droplet. State the
   size, region and monthly price and get an explicit yes first. First boot
   takes 2–5 minutes; `devbox up` waits for it.
6. **Verify.**
   - `devbox status`: droplet `active`, firewall lists one `/32`, tunnel `up`.
   - `docker context show` prints `devbox`; `docker info --format '{{.Name}}'`
     prints the droplet name, not `docker-desktop`.
   - `docker run --rm hello-world` succeeds.
   - From a project with a compose file: `devbox compose up -d --wait`, then
     connect to a forwarded port on `127.0.0.1` from the laptop.
7. **Explain the costs.** The droplet bills while it exists, even powered off.
   `devbox down` snapshots and deletes it; `devbox up` restores it.

## Migrating a project's containers

- Stop the project's local containers first (`docker --context desktop-linux
  compose down` in that directory), or the tunnel can't bind their ports. Data
  in local volumes doesn't move; seed or migrate again on the devbox.
- Add every port the project's apps connect to to `DEVBOX_FORWARD_PORTS` in
  `~/.config/devbox/config`, then `devbox tunnel restart`.
- Bind mounts (`./x:/y` in compose) need `devbox compose` (syncs the cwd) or
  `devbox sync <dir>`. Named volumes need nothing.
- Any compose service publishing on `0.0.0.0` explicitly stays unreachable from
  outside (cloud firewall + `DOCKER-USER` rule), but point it out to the user.

## Rules

- `devbox up` (billing), `devbox destroy` (data loss), and `devbox down`
  (deletes the droplet, takes a snapshot) need the user's go-ahead each time.
  Never pass `--yes` to `destroy` on your own initiative.
- Never set `DEVBOX_ALLOWED_CIDRS` to `0.0.0.0/0` or `::/0`, open other inbound
  ports, expose the Docker API over TCP, or turn on `StrictHostKeyChecking no`.
  If the user asks, explain the risk from `docs/SECURITY.md` first.
- If SSH reports a changed host key and devbox didn't just create the droplet,
  stop and tell the user; don't delete the `known_hosts` entry to get past it.
- Never commit anything from `~/.config/devbox` or any key material. This repo
  is public.
- devbox only acts on DigitalOcean resources whose name/tag equals
  `DEVBOX_NAME` (and snapshots named `<name>-YYYYMMDD-HHMMSS`). Keep that
  invariant: the account may hold production resources.

## Developing devbox

- Keep `bin/devbox` bash 3.2 compatible (macOS `/bin/bash`): no associative
  arrays, `mapfile`, `${var,,}`, or `&` in `${var//…}` replacements.
- `shellcheck -x bin/devbox install.sh` must pass (CI runs it).
- Validate anything that reaches a remote shell, `sed`, or `awk` replacement
  (see `load_config` and `ssh_pubkey`).
- `lib/cloud-init.yaml` must stay idempotent: it re-runs when a droplet is
  restored from a snapshot.
