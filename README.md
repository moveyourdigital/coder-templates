# Coder templates

Templates for [Coder](https://coder.com).
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
| Security rebuild (automatic, `scan.yml`; `build/` unchanged) | Patch | New patch tag |

The image tag is set in `main.tf` (`docker_image.workspace.name`).

## Workflow

Prerequisites: an `ops` workspace (or any machine) with `git`, `just`,
`docker` (for `just wait-image`) and `coder login`.

1. Create a branch, make the change, run `just lint` and `just validate`,
   open a pull request.
2. For a change under `build/`: bump the image tag in `main.tf`
   (`just check-tags` checks this).
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

### Template variables

Values for Terraform variables live in `vars.yaml` (repository root, not in
Git). `just push` and `just release` pass it with `--variables-file` when it
exists. Coder does not keep values between versions: a push without a value
resets the variable to its default.

Create it once on each machine you release from (see `vars.example.yaml`):

```yaml
extra_git_hosts: <git-host>   # space-separated, added to known_hosts
```

Every template must declare each variable in the file.

## Pull request checks

`.github/workflows/checks.yml` runs on each pull request to `main`
(read-only, nothing is pushed):

- `checks`: `just lint` and `just validate`, with the tools from `.mise.toml`.
  `just lint` includes `shellcheck`, `actionlint` and `zizmor` (security
  audit of the workflows; actions are pinned by commit SHA).
- `image-tag`: `just check-tags`. A change under `build/` needs a new image
  tag. A new tag must not be in GHCR yet, unless that image was built from
  the same `build/` (see below).
- `images`: builds each image that has a new tag, scans it with trivy and
  runs `tests/smoke.sh` (tools, Claude Code policy readable by `coder`,
  code-server starts). Locally: `just build-local <t>`, then `just smoke <t>`.

Make these checks required in the branch protection of `main`.

## Scheduled scan and updates

- `.github/workflows/scan.yml` scans the published images (the tags in
  `main.tf`) with trivy every day. New CVEs appear after a build. On a
  fixable CRITICAL vulnerability it rebuilds the image automatically:
  1. Rebuild `build/` from `main` with no cache and a fresh base image.
  2. trivy must be clean and `tests/smoke.sh` must pass.
  3. Push the next patch tag (for example `v0.6.0` → `v0.6.1`).
  4. Open a PR (`auto/rebuild-<template>-<tag>`) that bumps the tag in
     `main.tf` and enable auto-merge.
  5. **You** click "Approve workflows to run" on the PR. GitHub holds the
     checks of a PR opened by GitHub Actions until a person approves them.
  6. The PR merges itself when the required checks pass.

  If the rebuilt image is still vulnerable (for example a CVE in code that
  code-server bundles), the job fails and a person must fix `build/`.
  Releasing the new version in Coder stays manual: `just release`.
  To test the flow: Actions → scan → Run workflow → `rebuild: <template>`.
- The daily scan also uploads fixable HIGH and CRITICAL findings of each
  published image to the Security tab (Security → Code scanning, category
  `trivy-<template>`). Alerts close by themselves when a new image no
  longer has them. HIGH is for visibility only: it does not start a rebuild.
- Repository settings for the rebuild: "Allow auto-merge" (Settings →
  General) and "Allow GitHub Actions to create and approve pull requests"
  (Settings → Actions → General).
- `just check-tags` accepts a tag that is already in GHCR only if the image
  was built from the same `build/` (its `org.opencontainers.image.revision`
  label). This allows the rebuild PRs and rollbacks, never a re-push.
- Renovate (`renovate.json`) opens update PRs for GitHub Actions (SHA pins),
  the base image, code-server, trivy, `.mise.toml` tools and Terraform
  providers, 14 days after release. A PR that changes `build/` needs a new
  image tag in `main.tf` before the merge (`image-tag` fails until then).

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
