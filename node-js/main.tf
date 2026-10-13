terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.19"
    }
    # v4 builds with buildx over the local socket and ignores "host".
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6"
    }
  }
}

provider "docker" {
  # docker-x1 = docker-socket-proxy in the coder stack, pinned to x1-hel1.
  # Only the Coder provisioner uses it. Workspaces get NO access to it.
  host = "tcp://docker-x1:2375"
}

variable "extra_git_hosts" {
  description = "Space-separated extra Git hosts to add to known_hosts (e.g. a private Git server)."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[A-Za-z0-9. :-]*$", var.extra_git_hosts))
    error_message = "Use only host names or IP addresses, separated by spaces."
  }
}

locals {
  template_slug = "node"
  preview_port  = 3000
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# --- GitHub (enable after CODER_EXTERNAL_AUTH_0_* is set on the server) -----
# data "coder_external_auth" "github" {
#   id       = "github"
#   optional = true
# }

# --- Parameters -------------------------------------------------------------

data "coder_parameter" "repo_url" {
  name         = "repo_url"
  display_name = "Git repository URL"
  description  = "Optional. SSH or HTTPS URL to clone into ~/project on first boot."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 1
}

data "coder_parameter" "git_ref" {
  name         = "git_ref"
  display_name = "Git ref (branch, tag, or commit)"
  description  = "Optional. Checked out on every start. Leave blank for the default branch."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 2
}

data "coder_parameter" "node_version" {
  name         = "node_version"
  display_name = "Node.js"
  description  = "Global Node.js via mise. A .mise.toml / .nvmrc in the repo wins inside ~/project."
  type         = "string"
  default      = "node@lts"
  mutable      = true
  order        = 10
  option {
    name  = "LTS"
    value = "node@lts"
  }
  option {
    name  = "22"
    value = "node@22"
  }
}

data "coder_parameter" "extra_mise_tools" {
  name         = "extra_mise_tools"
  display_name = "Extra mise tools"
  description  = "Space-separated mise specs, e.g. `bun@latest python@3.13`."
  type         = "string"
  default      = "pnpm@latest"
  mutable      = true
  order        = 11
}

# --- Agent ------------------------------------------------------------------

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"

  env = {
    REPO_URL   = data.coder_parameter.repo_url.value
    GIT_REF    = data.coder_parameter.git_ref.value
    MISE_TOOLS = "${data.coder_parameter.node_version.value} ${data.coder_parameter.extra_mise_tools.value}"
  }

  # Git over SSH uses `coder gitssh` (GIT_SSH_COMMAND is set by the agent).
  # Add the Coder public key (`coder publickey`) once to GitHub and OneDev.
  startup_script = <<-EOT
    #!/usr/bin/env bash
    set -eu
    trap 'echo "ERR: startup_script failed at line $LINENO" >&2' ERR

    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    touch "$HOME/.ssh/known_hosts"
    ssh-keyscan -t ed25519,rsa ${var.extra_git_hosts} github.com gitlab.com \
      >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
    sort -u -o "$HOME/.ssh/known_hosts" "$HOME/.ssh/known_hosts"
    chmod 600 "$HOME/.ssh/known_hosts"

    # --- mise ---
    if [ ! -x "$HOME/.local/bin/mise" ]; then
      curl -fsSL https://mise.run | sh
    fi
    export PATH="$HOME/.local/bin:$PATH"
    grep -q 'mise activate bash' "$HOME/.bashrc" 2>/dev/null || \
      printf '\neval "$(~/.local/bin/mise activate bash)"\n' >> "$HOME/.bashrc"
    eval "$(mise activate bash)"
    for tool in $MISE_TOOLS; do
      [ -n "$tool" ] || continue
      mise use --global "$tool" || echo "WARN: failed to install $tool" >&2
    done

    # --- zsh + Oh My Zsh (home volume; plugin "git" gives gst, gco, ...) ---
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
      git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" \
        || echo "WARN: Oh My Zsh install failed" >&2
    fi
    if [ ! -f "$HOME/.zshrc" ] && [ -f "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" ]; then
      cp "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$HOME/.zshrc"
    fi
    if [ -f "$HOME/.zshrc" ]; then
      grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc" || \
        printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshrc"
      grep -q 'mise activate zsh' "$HOME/.zshrc" || \
        printf 'eval "$(~/.local/bin/mise activate zsh)"\n' >> "$HOME/.zshrc"
    fi

    # External plugins (cloned once into the home volume)
    ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
    for repo in zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting; do
      name="$(basename "$repo")"
      [ -d "$ZSH_CUSTOM/plugins/$name" ] || \
        git clone --depth=1 "https://github.com/$repo.git" "$ZSH_CUSTOM/plugins/$name" \
        || echo "WARN: $name install failed" >&2
    done

    # Default plugin list, set only while .zshrc still has the stock line.
    # Users can change it later; the script then leaves it alone.
    if [ -f "$HOME/.zshrc" ] && grep -q '^plugins=(git)$' "$HOME/.zshrc"; then
      sed -i 's/^plugins=(git)$/plugins=(git docker docker-compose npm gh sudo extract colored-man-pages history-substring-search zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"
    fi

    # --- Claude Code (native installer, home volume) ---
    # Login once with `claude`. ~/.claude persists; the VS Code extension
    # uses the same credentials.
    if [ ! -x "$HOME/.local/bin/claude" ]; then
      curl -fsSL https://claude.ai/install.sh | bash || echo "WARN: Claude Code install failed" >&2
    fi

    git config --global user.name  "${data.coder_workspace_owner.me.full_name}"
    git config --global user.email "${data.coder_workspace_owner.me.email}"
    git config --global init.defaultBranch main

    # --- Repository ---
    if [ -n "$REPO_URL" ] && [ ! -d "$HOME/project/.git" ]; then
      git clone "$REPO_URL" "$HOME/project" || true
    fi
    if [ -n "$GIT_REF" ] && [ -d "$HOME/project/.git" ]; then
      (cd "$HOME/project" \
        && git fetch --all --tags --quiet \
        && git checkout "$GIT_REF" \
        && git pull --ff-only 2>/dev/null) || \
        echo "WARN: failed to apply git_ref='$GIT_REF' (dirty tree?)" >&2
    fi

    # --- Dependencies ---
    if [ -d "$HOME/project" ]; then
      cd "$HOME/project"
      mise install 2>/dev/null || true
      if [ -f "package.json" ]; then
        if   [ -f "pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then pnpm install || true
        elif [ -f "yarn.lock" ]      && command -v yarn >/dev/null 2>&1; then yarn install || true
        elif [ -f "bun.lockb" ]      && command -v bun  >/dev/null 2>&1; then bun  install || true
        elif command -v npm >/dev/null 2>&1; then npm install || true
        fi
      fi
    fi

    # --- Inner Docker housekeeping ---
    if timeout 60 sh -c 'until docker info >/dev/null 2>&1; do sleep 1; done'; then
      docker system prune -f --filter until=168h >/dev/null || true
    else
      echo "WARN: inner dockerd not ready, see /tmp/dockerd.log" >&2
    fi
  EOT

  metadata {
    display_name = "CPU"
    key          = "cpu"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Memory"
    key          = "mem"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Disk"
    key          = "disk"
    script       = "coder stat disk --path $HOME"
    interval     = 60
    timeout      = 1
  }
}

# --- Inner Docker daemon ----------------------------------------------------

resource "coder_script" "dockerd" {
  agent_id           = coder_agent.main.id
  display_name       = "dockerd"
  icon               = "/icon/docker.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/usr/bin/env bash
    set -eu
    exec sudo dockerd > /tmp/dockerd.log 2>&1
  EOT
}

# --- code-server ------------------------------------------------------------

resource "coder_script" "code_server" {
  agent_id           = coder_agent.main.id
  display_name       = "code-server"
  icon               = "/icon/code.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/usr/bin/env bash
    set -eu
    if ! code-server --list-extensions 2>/dev/null | grep -qi '^anthropic.claude-code$'; then
      code-server --install-extension anthropic.claude-code || echo "WARN: extension install failed" >&2
    fi
    FOLDER="$HOME"
    [ -d "$HOME/project" ] && FOLDER="$HOME/project"
    exec /usr/local/bin/code-server --auth none --bind-addr 127.0.0.1:13337 "$FOLDER"
  EOT
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code (web)"
  url          = "http://localhost:13337/?folder=/home/coder/project"
  icon         = "/icon/code.svg"
  subdomain    = true
  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "coder_app" "preview" {
  agent_id     = coder_agent.main.id
  slug         = "preview"
  display_name = "Preview :${local.preview_port}"
  url          = "http://localhost:${local.preview_port}"
  icon         = "/icon/widgets.svg"
  subdomain    = true
  share        = "owner"
}

# --- Volumes ----------------------------------------------------------------

# DO NOT rename this resource or change the name expression: existing
# workspaces keep their home only while both stay identical.
resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
}

# Inner Docker state. Rebuildable. Borg exclude: coder-*-docker.
resource "docker_volume" "docker_data" {
  name = "coder-${data.coder_workspace.me.id}-docker"
  lifecycle {
    ignore_changes = all
  }
}

# --- Image ------------------------------------------------------------------

resource "docker_image" "workspace" {
  # Built from build/ by GitHub Actions (.github/workflows/images.yml) and
  # pushed to GHCR. Not built on x1-hel1. Tags are immutable: a change under
  # build/ needs a new tag here.
  name         = "ghcr.io/moveyourdigital/coder-workspace-node:v0.5.0"
  keep_locally = true
}

# --- Workspace container ----------------------------------------------------

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.workspace.image_id
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = lower(data.coder_workspace.me.name)

  # Sysbox: own dockerd inside, user namespace, no host socket.
  # Do not add privileged, capabilities, security_opts or network_mode=host.
  runtime = "sysbox-runc"

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]

  entrypoint = ["sh", "-c", coder_agent.main.init_script]

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home.name
  }
  volumes {
    container_path = "/var/lib/docker"
    volume_name    = docker_volume.docker_data.name
  }
}
