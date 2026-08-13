ARG BASE_IMAGE=node:22-bookworm-slim@sha256:f32b81066cde10a75dbac96646099533316d94bac4150c55da1636e1f0ffdc46
FROM ${BASE_IMAGE}

ARG DEV_USER=developer
ARG DEV_UID=1000
ARG DEV_GID=1000
ARG DEV_HOME=/home/developer
ARG DEV_TZ=UTC
ARG TARGET_NODE_VERSION=24.18.1
ARG TARGET_PNPM_VERSION=11.21.0
ARG TARGET_CLAUDE_VERSION=latest
ARG CLAUDE_BINARY_SEED=0
ARG PNPM_SHA256=87237d37eadb79dc626a0576eb3a52d23d70422c323ae5e00fc05c91f4323780
ARG DEBIAN_MIRROR=http://deb.debian.org/debian
ARG DEBIAN_SECURITY_MIRROR=http://deb.debian.org/debian-security

ENV TZ=${DEV_TZ} \
    HOME=${DEV_HOME} \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    NODE_VERSION=${TARGET_NODE_VERSION} \
    PNPM_VERSION=${TARGET_PNPM_VERSION} \
    NPM_CONFIG_PREFIX=${DEV_HOME}/.local \
    PATH=${DEV_HOME}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    case "${DEV_USER}" in ''|*[!a-zA-Z0-9_-]*) exit 1 ;; esac; \
    case "${DEV_UID}:${DEV_GID}" in *[!0-9:]*) exit 1 ;; esac; \
    case "${DEV_HOME}" in /*) ;; *) exit 1 ;; esac; \
    test -f "/usr/share/zoneinfo/${DEV_TZ}"; \
    sed -i \
        -e "s|^URIs: http://deb.debian.org/debian$|URIs: ${DEBIAN_MIRROR}|" \
        -e "s|^URIs: http://deb.debian.org/debian-security$|URIs: ${DEBIAN_SECURITY_MIRROR}|" \
        /etc/apt/sources.list.d/debian.sources; \
    apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 update; \
    apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 install -y --no-install-recommends \
        bash build-essential ca-certificates curl dnsutils fd-find file git iproute2 \
        iputils-ping jq less libssl-dev lsof locales netcat-openbsd net-tools \
        openssh-client pkg-config procps psmisc python3 python3-pip python3-venv \
        ripgrep rsync tzdata unzip xz-utils zip; \
    sed -i 's/^# \(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen; \
    locale-gen; \
    ln -snf "/usr/share/zoneinfo/${DEV_TZ}" /etc/localtime; \
    printf '%s\n' "${DEV_TZ}" > /etc/timezone; \
    case "$(dpkg --print-architecture)" in \
        amd64) node_arch=x64; node_sha256=d6c664df3f3f61458e8c277585571328522d705166723a7c7823a9253a4d15a0 ;; \
        arm64) node_arch=arm64; node_sha256=7201e3a09dc825bac57867c81913e2b8f0ef87d04cb9082af4cda82f6ff3d88c ;; \
        *) echo 'Only amd64 and arm64 are supported' >&2; exit 1 ;; \
    esac; \
    curl -fsSL --http1.1 --retry 3 --retry-all-errors --connect-timeout 15 -o /tmp/node.tar.xz \
        "https://nodejs.org/dist/v${TARGET_NODE_VERSION}/node-v${TARGET_NODE_VERSION}-linux-${node_arch}.tar.xz"; \
    printf '%s  %s\n' "${node_sha256}" /tmp/node.tar.xz | sha256sum -c -; \
    tar -xJf /tmp/node.tar.xz --strip-components=1 -C /usr/local; \
    corepack enable; \
    curl -fsSL --http1.1 --retry 3 --retry-all-errors --connect-timeout 15 -o /tmp/pnpm.tgz \
        "https://registry.npmjs.org/pnpm/-/pnpm-${TARGET_PNPM_VERSION}.tgz"; \
    printf '%s  %s\n' "${PNPM_SHA256}" /tmp/pnpm.tgz | sha256sum -c -; \
    groupmod --new-name "${DEV_USER}" --gid "${DEV_GID}" node; \
    install -d "$(dirname "${DEV_HOME}")"; \
    usermod --login "${DEV_USER}" --uid "${DEV_UID}" --gid "${DEV_GID}" \
        --home "${DEV_HOME}" --move-home node; \
    install -d -o "${DEV_UID}" -g "${DEV_GID}" /workspace \
        "${DEV_HOME}/.local/bin" "${DEV_HOME}/.local/lib/node_modules/pnpm"; \
    tar -xzf /tmp/pnpm.tgz -C "${DEV_HOME}/.local/lib/node_modules/pnpm" --strip-components=1; \
    ln -s ../lib/node_modules/pnpm/bin/pnpm.mjs "${DEV_HOME}/.local/bin/pnpm"; \
    ln -s ../lib/node_modules/pnpm/bin/pnpx.mjs "${DEV_HOME}/.local/bin/pnpx"; \
    ln -s /usr/bin/fdfind /usr/local/bin/fd; \
    chown -R "${DEV_UID}:${DEV_GID}" "${DEV_HOME}"; \
    rm -f /tmp/node.tar.xz /tmp/pnpm.tgz; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

ENV USER=${DEV_USER} LOGNAME=${DEV_USER}
USER ${DEV_USER}
WORKDIR ${HOME}

COPY claude-seed /tmp/claude-seed
RUN set -eux; \
    claude_dir="$HOME/.local/share/claude/versions"; \
    install -d "$claude_dir"; \
    case "${CLAUDE_BINARY_SEED}" in \
        0) \
            release_base=https://downloads.claude.ai/claude-code-releases; \
            case "${TARGET_CLAUDE_VERSION}" in \
                latest|stable) \
                    claude_version="$(curl -fsSL --http1.1 --retry 3 --connect-timeout 15 \
                        --max-time 120 "$release_base/${TARGET_CLAUDE_VERSION}")" \
                    ;; \
                *) claude_version="${TARGET_CLAUDE_VERSION}" ;; \
            esac; \
            case "$claude_version" in \
                [0-9]*.[0-9]*.[0-9]*) ;; \
                *) echo "Invalid Claude Code version: $claude_version" >&2; exit 1 ;; \
            esac; \
            case "$(dpkg --print-architecture)" in \
                amd64) claude_platform=linux-x64 ;; \
                arm64) claude_platform=linux-arm64 ;; \
                *) echo 'Only amd64 and arm64 are supported' >&2; exit 1 ;; \
            esac; \
            manifest="$(curl -fsSL --http1.1 --retry 3 --connect-timeout 15 --max-time 120 \
                "$release_base/$claude_version/manifest.json")"; \
            claude_sha256="$(printf '%s' "$manifest" | jq -r \
                --arg platform "$claude_platform" '.platforms[$platform].checksum // empty')"; \
            case "$claude_sha256" in \
                [0-9a-f][0-9a-f]*) test "${#claude_sha256}" -eq 64 ;; \
                *) echo "Missing checksum for $claude_platform" >&2; exit 1 ;; \
            esac; \
            curl -fsSL --http1.1 --retry 3 --retry-all-errors --connect-timeout 15 --max-time 1200 \
                --speed-time 60 --speed-limit 1024 \
                -o "$claude_dir/$claude_version" \
                "$release_base/$claude_version/$claude_platform/claude"; \
            printf '%s  %s\n' "$claude_sha256" "$claude_dir/$claude_version" | sha256sum -c -; \
            chmod 755 "$claude_dir/$claude_version" \
            ;; \
        1) \
            test -s /tmp/claude-seed; \
            claude_version="$(/tmp/claude-seed --version | awk 'NR == 1 { print $1 }')"; \
            case "$claude_version" in \
                [0-9]*.[0-9]*.[0-9]*) ;; \
                *) echo "Invalid Claude Code seed version: $claude_version" >&2; exit 1 ;; \
            esac; \
            install -m 755 /tmp/claude-seed "$claude_dir/$claude_version" \
            ;; \
        *) echo "Invalid CLAUDE_BINARY_SEED: ${CLAUDE_BINARY_SEED}" >&2; exit 1 ;; \
    esac; \
    ln -s "$claude_dir/$claude_version" "$HOME/.local/bin/claude"; \
    rm -f /tmp/claude-seed; \
    claude --version

USER root
RUN ln -s /usr/sbin/ifconfig /usr/local/bin/ifconfig
USER ${DEV_USER}

CMD ["bash"]
