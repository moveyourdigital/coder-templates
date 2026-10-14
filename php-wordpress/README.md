---
display_name: PHP / WordPress
description: PHP 8.3, Composer, WP-CLI and Node.js with Docker inside the workspace (Sysbox). For WordPress themes, plugins and PHP apps.
icon: /emojis/1f418.png
verified: false
tags: [php, wordpress, docker, sysbox, claude-code]
---

# PHP / WordPress

A workspace for PHP and WordPress development. Each workspace has its own
Docker daemon, so you can run WordPress, MariaDB and other services with
`docker compose`, without access to the host.

## What you get

| Area | Tools |
|---|---|
| PHP | PHP 8.3 CLI with common extensions (mysql, pgsql, sqlite, gd, imagick, redis, intl, mbstring, xml, zip, soap, bcmath) |
| PHP tools | Composer, WP-CLI (`wp`), `mariadb-client` |
| Node.js | Node LTS through [mise](https://mise.jdx.dev), for theme and asset builds |
| Docker | Docker Engine, Compose and Buildx **inside** the workspace |
| Editor | VS Code (web) with the Claude Code extension |
| AI | Claude Code CLI (`claude`), with skills for OneDev |
| Git | `git`, GitHub CLI (`gh`), OneDev CLI (`tod`), SSH through Coder |
| Other | `build-essential`, `ripgrep`, `fd`, `jq`, `tmux`, `htop` |

## Parameters

| Parameter | Default | Description |
|---|---|---|
| Git repository URL | empty | Repository to clone into `~/project` on the first start |
| Git ref | empty | Branch, tag or commit to check out on each start |
| Node.js | `node@lts` | Global Node.js version |
| Extra mise tools | empty | More tools, for example `pnpm@latest python@3.13` |

On each start, the workspace runs `mise install`, `npm`/`pnpm`/`yarn`/`bun install`
(by lockfile) and `composer install` in `~/project`, if the files exist.

## First steps

1. **Add your Coder SSH key to GitHub and OneDev.** Copy it from
   **Account → SSH Keys** in Coder. Git in the workspace uses this key. Do not
   copy private keys into the workspace.
2. **Log in to Claude Code once.** Open a terminal and run `claude`. The login
   is kept in `~/.claude`. The VS Code extension uses the same login.
3. **Connect `tod` to OneDev (optional).** In OneDev, create an access token
   (your avatar → **Access Tokens**), then run
   `tod config set access-token <token>`. The server URL is already set. Test
   it with `tod project list`. Claude Code can then work with OneDev issues,
   pull requests and builds through its `tod` skills. It asks before any change.
4. **Start WordPress locally.** Use a `compose.yaml` in your project, then
   open the **Preview :8080** app in the Coder dashboard.

Example `compose.yaml`:

```yaml
services:
  db:
    image: mariadb:11
    environment:
      MARIADB_DATABASE: wordpress
      MARIADB_USER: wordpress
      MARIADB_PASSWORD: wordpress
      MARIADB_ROOT_PASSWORD: root
    volumes:
      - db:/var/lib/mysql
  wordpress:
    image: wordpress:php8.3-apache
    depends_on: [db]
    ports:
      - "8080:80"
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_NAME: wordpress
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: wordpress
    volumes:
      - ./:/var/www/html/wp-content/themes/my-theme
volumes:
  db:
```

## What persists

| Location | Persists after stop/start? |
|---|---|
| `/home/coder` (projects, mise tools, `~/.claude`, settings) | Yes |
| Docker images, containers and volumes inside the workspace | Yes |
| Packages from `sudo apt install` | **No.** The container is created again on each start |

Install tools with mise, not with apt:

```bash
mise use --global java@temurin-21
mise use --global npm:@wordpress/env
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
coder templates push php-wordpress -d . --name <version-name>
```

A change in any file under `build/` rebuilds the image on the next workspace
build. Users get the new version when they update their workspace.