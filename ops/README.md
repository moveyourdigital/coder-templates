---
display_name: Ops / GitOps
description: Infrastructure workspace — Hetzner, Cloudflare, Terraform, Docker Swarm, Ansible, Tailscale (Headscale). No credentials in the template.
icon: /emojis/1f6e0.png
verified: false
tags: [ops, gitops, terraform, hetzner, cloudflare, swarm, sysbox]
---

# Ops / GitOps

A workspace for infrastructure work: Hetzner Cloud and Robot, DNS, Cloudflare,
the Docker Swarm, host configuration, backups and image security.

Same base as the `node` template: own Docker daemon (Sysbox), zsh with Oh My
Zsh, mise, VS Code (web) and Claude Code.

**The template has no credentials.** Each user logs in to each tool once, in
their own workspace. Credentials stay in that workspace's home volume.

## Tools

| Area | Tools | Installed by |
|---|---|---|
| Hetzner | `hcloud` (Cloud + DNS), `curl` + `jq` (Robot API) | mise / apt |
| IaC | `terraform`, `tflint` | mise |
| Cloudflare | `wrangler`, `cloudflared` | mise |
| Swarm | Docker CLI + `docker context`, `dive`, `crane` | apt / mise |
| Security | `trivy` (images, IaC, lockfiles), `gitleaks` | mise |
| GitOps | `sops`, `age`, `pre-commit`, `yamllint`, `shellcheck`, `hadolint`, `actionlint` | mise / apt |
| Hosts | `ansible` | apt |
| Network | Tailscale client, `mtr`, `tcpdump`, `nmap`, `iperf3`, `socat`, `whois`, `openssl` | apt |
| Data | `borgbackup`, `postgresql-client`, `redis-tools` | apt |
| Runbooks | `just` | mise |
| Base | Node LTS, `gh`, Claude Code, code-server | mise / apt |

mise tool versions are pinned in `main.tf` (`local.ops_tools`).

ClickHouse client is not installed (large package). Use it from Docker:

```bash
docker run --rm -it clickhouse/clickhouse-server clickhouse-client --host <host>
```

## First steps (once per workspace)

### 1. Tailscale (Headscale)

The nodes have port 22 closed to the internet. The workspace joins the
tailnet as its own node, in userspace mode.

```bash
tailscale up --login-server=https://<headscale-url> --hostname=ops-$(hostname)
tailscale status
```

Give this node only the access it needs in the Headscale ACL.

### 2. SSH to the nodes

Create a dedicated key for this workspace and add its public part to the
nodes (deploy user):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/ops_ed25519 -C "ops@$(hostname)"
```

`~/.ssh/config`:

```
Host m1-hel1 x1-hel1 w1-hel1
  User root
  IdentityFile ~/.ssh/ops_ed25519
  ProxyCommand tailscale --socket=%d/.local/share/tailscale/tailscaled.sock nc %h %p
```

Test: `ssh m1-hel1 hostname`.

### 3. Docker context for the Swarm

```bash
docker context create swarm --docker host=ssh://m1-hel1
docker --context swarm service ls
```

Use `--context swarm` per command, or `docker context use swarm` with care.

### 4. Hetzner, Cloudflare, Coder

```bash
hcloud context create moveyourdigital      # paste a project token
wrangler login                             # or CLOUDFLARE_API_TOKEN in a local .env
coder login https://coder.moveyourdigital.dev
```

Use tokens with the minimum scope for the task.

## Credentials: where they live

| Credential | Location |
|---|---|
| Hetzner Cloud token | `~/.config/hcloud/cli.toml` |
| Cloudflare login | `~/.wrangler/` or `~/.config/.wrangler/` |
| Tailscale node | `~/.local/share/tailscale/` |
| SSH key to nodes | `~/.ssh/ops_ed25519` |
| Coder session | `~/.config/coderv2/` |

Do **not** store these as Coder user secrets: user secrets go to every
workspace you own, including the coding workspaces.

## Claude Code policy

This template has a stricter managed policy than the coding templates:

- **Denied:** `sudo`, `terraform destroy`, `hcloud * delete`, `docker stack rm`,
  `docker service rm`, `docker node rm`, volume removal, `docker system prune`,
  `wrangler delete`, `borg delete/prune`, `tailscale logout`, and reading the
  credential files listed above.
- **Asks first:** `terraform apply`, all `hcloud` commands, `docker stack deploy`,
  `docker service update/scale`, `docker node update`, `docker context use`,
  `ansible-playbook`, `wrangler deploy/secret`, `coder templates push`,
  `ssh`, `scp`, `rsync`.

The policy is a safety net, not a security boundary. Review every action that
changes infrastructure.

## What persists

| Location | Persists after stop/start? |
|---|---|
| `/home/coder` (repo, tools, logins, Tailscale state) | Yes (backed up) |
| Docker images inside the workspace | Yes (not backed up) |
| `sudo apt install` | No |

## For template owners

- Runtime `sysbox-runc` on `x1-hel1`. No host Docker socket.
- Image `coder-workspace-ops:<tag>`, built on x1 from `build/`:
  `docker build -t coder-workspace-ops:<tag> build/`
- `tailscaled` runs as the `coder` user in userspace mode (no TUN device),
  with a SOCKS5 proxy on `localhost:1055`.
- To change a pinned tool version: edit `local.ops_tools` and publish a patch
  version. No image rebuild.
