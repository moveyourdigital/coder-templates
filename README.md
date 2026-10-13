# Coder templates — Move Your Digital

Templates for [Coder](https://coder.com) at `coder.moveyourdigital.dev`.
Workspaces run on `x1-hel1` (Docker Swarm worker) with the
[Sysbox](https://github.com/nestybox/sysbox) runtime: each workspace has its
own Docker daemon, with no access to the host Docker socket.

| Template | For | Image |
|---|---|---|
| [`node-js`](node-js/) | Node.js LTS / Next.js | `ghcr.io/moveyourdigital/coder-workspace-node` |
| [`php-wordpress`](php-wordpress/) | PHP 8.3 / WordPress | `ghcr.io/moveyourdigital/coder-workspace-php-wordpress` |
| [`ops`](ops/) | Infrastructure and GitOps (owner only) | `ghcr.io/moveyourdigital/coder-workspace-ops` |

**This repository is the source of truth.** Do not edit templates in the
Coder UI. A change made there is lost on the next push from Git.

## Layout

```
<template>/
  main.tf                       Coder template (agent, apps, volumes, container)
  README.md                     Shown in the Coder dashboard
  build/Dockerfile              Workspace image
  build/daemon.json             Inner Docker daemon config
  build/managed-settings.json   Claude Code managed policy
```

## Versions

Template versions use `vMAJOR.MINOR.PATCH`. Each published version has a Git
tag `<template>/<version>`, for example `node-js/v0.4.1`.

| Change | Version | Image tag |
|---|---|---|
| `main.tf` only (script, parameter, pinned mise tool) | Patch | Unchanged |
| Anything under `build/` | Minor | New tag = new version |
| Breaking for users (volumes, removed tools) | Major | New tag = new version |

The image tag is set in `main.tf` (`docker_image.workspace.name`).

## Workflow

Prerequisites: an `ops` workspace (or any machine) with `git`, `just`,
`docker` (for `just wait-image`) and `coder login`.

1. Create a branch, make the change, run `just lint`, open a pull request.
2. For a change under `build/`: bump the image tag in `main.tf`.
3. After the merge: wait for the `images` workflow:
   ```bash
   just wait-image node-js
   ```
4. Publish the template version and push the Git tag:
   ```bash
   just release node-js v0.4.1 "Short description of the change"
   ```
   This checks that the image exists in GHCR, publishes the template
   version, and pushes the Git tag.
5. Update the workspaces (Coder dashboard → Update, or `coder update <ws>`).

Other commands: `just --list`.

## Images

- Built by GitHub Actions (`.github/workflows/images.yml`) on push to `main`
  when `*/build/**` or `*/main.tf` changes (also by manual dispatch).
- Pushed to GHCR as `ghcr.io/moveyourdigital/coder-workspace-<name>:<tag>`
  (public packages). The templates pull the image from there.
- Scanned with trivy before the push. The build fails on a fixable CRITICAL
  vulnerability.
- Tags are immutable. An existing tag is never rebuilt: a change under
  `build/` needs a new tag in `main.tf`.
- The workflow uses only `GITHUB_TOKEN`. No secrets in the repo or images.
- Images are not built in Terraform: Docker on `x1-hel1` uses the containerd
  image store (BuildKit only), and the `kreuzwerker/docker` provider (v3)
  cannot open a BuildKit session.
- To test a Dockerfile locally: `just build-local <template>`.

## Host requirements (x1-hel1)

- Sysbox CE 0.7.1, Docker 29.8.2, both on `apt-mark hold`.
- Host `daemon.json`: `features.time-namespaces: false`
  (nestybox/sysbox#1011).
- Backups: `coder-*-home` volumes are backed up; `coder-*-docker` volumes,
  `/var/lib/sysbox` and `/var/lib/containerd` are excluded.

## Security rules

- No credentials in templates. Users bring their own (Coder user secrets for
  low-risk tokens; the `ops` home for infrastructure credentials).
- Git over SSH uses the Coder key (`coder gitssh`). No private keys in images
  or scripts.
- Claude Code runs with a managed policy per template (`build/managed-settings.json`).
  The file must be readable by the `coder` user (`COPY --chmod=0644`).
