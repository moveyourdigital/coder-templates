# "php-wordpress" Coder workspace (Sysbox runtime): PHP 8.3 / WordPress.
# PHP from apt. Node (theme builds) is installed by mise at start.
# Run WordPress + MariaDB locally with docker compose inside the workspace.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/Lisbon \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# System packages. node-gyp needs python3 + build-essential.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git jq sudo openssh-client \
      gnupg lsb-release locales tzdata iptables procps file \
      build-essential pkg-config python3 \
      mariadb-client \
      vim less htop iputils-ping dnsutils netcat-openbsd \
      unzip zip rsync man-db tmux ripgrep fd-find zsh \
  && rm -rf /var/lib/apt/lists/* \
  && locale-gen en_US.UTF-8

# --- Docker Engine (inner daemon) -------------------------------------------
# Pinned and held: mixed versions break Docker inside Sysbox (sysbox#991).
ARG DOCKER_VERSION=5:29.8.2-1~ubuntu.24.04~noble
RUN install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
  && chmod a+r /etc/apt/keyrings/docker.gpg \
  && . /etc/os-release \
  && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
       > /etc/apt/sources.list.d/docker.list \
  && apt-get update && apt-get install -y --no-install-recommends \
       docker-ce=${DOCKER_VERSION} docker-ce-cli=${DOCKER_VERSION} \
       containerd.io docker-compose-plugin docker-buildx-plugin \
  && apt-mark hold docker-ce docker-ce-cli containerd.io \
  && rm -rf /var/lib/apt/lists/*

COPY daemon.json /etc/docker/daemon.json

# --- GitHub CLI -------------------------------------------------------------
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli.gpg \
  && chmod a+r /etc/apt/keyrings/githubcli.gpg \
  && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

# --- PHP 8.3 + Composer + WP-CLI --------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
       php8.3-cli \
       php8.3-xml php8.3-curl php8.3-zip php8.3-mbstring \
       php8.3-intl php8.3-gd php8.3-bcmath php8.3-soap \
       php8.3-mysql php8.3-pgsql php8.3-sqlite3 \
       php-imagick php-redis \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://getcomposer.org/installer \
       | php -- --install-dir=/usr/local/bin --filename=composer \
  && composer --version

RUN curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
       -o /usr/local/bin/wp \
  && chmod 0755 /usr/local/bin/wp \
  && wp --allow-root --version

# --- code-server ------------------------------------------------------------
ARG CODE_SERVER_VERSION=4.140.0
RUN curl -fsSL "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_amd64.deb" \
       -o /tmp/code-server.deb \
  && apt-get update && apt-get install -y --no-install-recommends /tmp/code-server.deb \
  && rm -f /tmp/code-server.deb \
  && rm -rf /var/lib/apt/lists/* \
  && ln -sf /usr/bin/code-server /usr/local/bin/code-server

# --- Claude Code managed policy ---------------------------------------------
COPY managed-settings.json /etc/claude-code/managed-settings.json

# --- coder user -------------------------------------------
# UID 1000 must stay: existing home volumes are owned by 1000.
RUN userdel -r ubuntu 2>/dev/null || true \
  && useradd --create-home --shell /bin/zsh --uid 1000 coder \
  && usermod -aG docker coder \
  && echo 'coder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/coder \
  && chmod 0440 /etc/sudoers.d/coder

USER coder
WORKDIR /home/coder