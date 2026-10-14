---
display_name: Node.js / Next.js
description: Node.js LTS with pnpm, Docker inside the workspace (Sysbox), VS Code (web) and Claude Code. For Next.js and other Node.js apps.
icon: /icon/nodejs.svg
verified: false
tags: [node, nextjs, docker, sysbox, claude-code]
---

# Node.js / Next.js

A workspace for Node.js and Next.js development. Each workspace has its own
Docker daemon, so you can run Postgres, Redis and other services with
`docker compose`, without access to the host.

## What you get

| Area | Tools |
|---|---|
| Node.js | Node LTS and pnpm through [mise](https://mise.jdx.dev) |
| Docker | Docker Engine, Compose and Buildx **inside** the workspace |
| Editor | VS Code (web) with the Claude Code extension |
| AI | Claude Code CLI (`claude`), with skills for OneDev |
| Git | `git`, GitHub CLI (`gh`), OneDev CLI (`tod`), SSH through Coder |
| Other | `build-essential`, `python3` (node-gyp), `ripgrep`, `fd`, `jq`, `tmux`, `htop` |

`NEXT_TELEMETRY_DISABLED=1` is set in the image.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| Git repository URL | empty | Repository to clone into `~/project` on the first start. Use the SSH URL |
| Git ref | empty | Branch, tag or commit to check out on each start |
| Node.js | `node@lts` | Global Node.js version |
| Extra mise tools | `pnpm@latest` | More tools, for example `bun@latest python@3.13` |

On each start, the workspace runs `mise install` and `npm`/`pnpm`/`yarn`/`bun install`
(by lockfile) in `~/project`, if the files exist. A `.mise.toml` or `.nvmrc`
in the repo wins over the parameter.

## First steps

1. **Add your Coder SSH key to GitHub and OneDev.** Copy it from
   **Account → SSH Keys** in Coder. Git in the workspace uses this key. Do not
   copy private keys into the workspace.
2. **Log in to Claude Code once.** Open a terminal and run `claude`. The login
   is kept in `~/.claude`. The VS Code extension uses the same login.
3. **Connect `tod` to OneDev (optional).** In OneDev, create an access token
   (your avatar → **Access Tokens**). Store it as a Coder user secret with the
   environment variable `ONEDEV_TOKEN`:
   `printf %s "<token>" | coder secret create onedev-token --env ONEDEV_TOKEN`.
   Restart the workspace, then test with `tod project list`. The OneDev URL is
   preset by the template. Claude Code can then work with OneDev issues, pull
   requests and builds through its `tod` skills. It asks before any change.
4. **Run the app.** Start the dev server on port 3000 (`pnpm dev`), then open
   the **Preview :3000** app in the Coder dashboard.

## What persists

| Location | Persists after stop/start? |
|---|---|
| `/home/coder` (projects, mise tools, `~/.claude`, settings) | Yes |
| Docker images, containers and volumes inside the workspace | Yes |
| Packages from `sudo apt install` | **No.** The container is created again on each start |

Install tools with mise, not with apt:

```bash
mise use --global java@temurin-21
mise use --global bun@latest
```

If a tool is only available from apt, ask the template owner to add it to
`build/Dockerfile`.

## Rules

- Ports that you publish with Docker stay **inside** the workspace. They do
  not open on the host or on the internet. Use the Coder apps or
  `coder port-forward` to reach them.
- Use your own Claude subscription or API key. Do not share logins.
- Claude Code runs with a managed policy: bypass mode and `sudo` are blocked.
- Do not keep production credentials in this workspace. Infrastructure work
  uses the separate `ops` template.

## How it works (for template owners)

- The workspace container runs with `runtime = "sysbox-runc"` on `x1-hel1`.
  Sysbox gives it a user namespace and its own `dockerd`. There is no host
  Docker socket and no privileged mode.
- Volumes per workspace:
  - `coder-<workspace-id>-home` → `/home/coder` (backed up)
  - `coder-<workspace-id>-docker` → `/var/lib/docker` (rebuildable, excluded from backup)
- The inner Docker daemon uses MTU 1400 and the address ranges `10.209.0.0/24`
  and `10.210.0.0/16`, so it does not collide with the host networks.
- Docker inside the image is pinned and held. Change `docker-ce`,
  `docker-ce-cli` and `containerd.io` together (see nestybox/sysbox#991).
- `features.time-namespaces` is `false` in the host and inner `daemon.json`
  (see nestybox/sysbox#1011).

### Files

```
main.tf                       Template (agent, apps, volumes, container)
build/Dockerfile              Workspace image
build/daemon.json             Inner Docker daemon config
build/managed-settings.json   Claude Code managed policy
```

### Update the template

```bash
coder templates push node -d . --name <version-name>
```

A change in any file under `build/` rebuilds the image on the next workspace
build. Users get the new version when they update their workspace.
