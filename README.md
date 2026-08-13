<p align="center">
  <img src="./assets/readme/hero.svg" width="100%" alt="claude-code-container: rebuild the Claude Code environment while keeping Home data, projects, and host-managed network policy">
</p>

<p align="center">
  <strong>A portable Linux development container for Claude Code with a persistent identity and a disposable runtime.</strong>
</p>

<p align="center">
  <a href="./LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-f4a261?style=flat-square"></a>
  <img alt="Linux amd64 and arm64" src="https://img.shields.io/badge/linux-amd64%20%7C%20arm64-222629?style=flat-square">
  <img alt="Docker required" src="https://img.shields.io/badge/runtime-Docker-222629?style=flat-square">
</p>

`claude-code-container` gives Claude Code a consistent Linux toolbox without turning
the container into the owner of your work. Rebuild the image when the toolchain
changes; keep login state and user-installed tools in a named volume; keep
projects on the host; let the host decide how network traffic is routed.

## Start here

### Requirements

- Linux on `amd64` or `arm64`
- Docker Engine available to the current user without `sudo`
- Bash, Python 3, and an OpenSSH server
- A writable `~/.ssh/authorized_keys`
- A host workspace at `~/work`, or a custom `CLAUDE_CODE_CONTAINER_WORKSPACE`

### Install

```bash
git clone https://github.com/ada20204/claude-code-container.git
cd claude-code-container
./install.sh
claude-code-container install
source ~/.bashrc
```

Enter the environment:

```bash
claude-container
```

The default directory is the container user's Home. Projects are available at
both `~/work` and `/workspace`. From inside the container, return to the host
with the generated key:

```bash
ssh host
```

Installation stops instead of replacing a conflicting `Host host` entry,
`claude-container` alias, or `~/work` path. It reports success only after a real
non-interactive SSH connection back to the host succeeds.

## What stays when the container goes away

<p align="center">
  <img src="./assets/readme/architecture.svg" width="100%" alt="Architecture showing the disposable container connected to a persistent Home volume, host workspace, restricted host SSH, and host-managed network routing">
</p>

The image contains Claude Code and the development toolbox. The running
container is disposable. State is divided deliberately:

- **Persistent Home** stores Claude login state, `~/.claude/CLAUDE.md`, the
  container-to-host SSH key, and user-level tools under `~/.local`.
- **Host workspace** keeps projects under the host's `~/work` and mounts them
  read-write at `/workspace`; `~/work` inside the container is a symlink to it.
- **Host network policy** receives normal Docker bridge egress. No proxy URL,
  node, account, or Mihomo configuration is baked into the image.
- **Disposable runtime** can be removed or rebuilt without moving project data
  into a Docker volume.

## Network model

Runtime traffic follows this path:

```text
Claude Code container
  -> Docker bridge
  -> host network stack / NAT
  -> host routing, TUN, firewall, or proxy policy
  -> selected destination
```

This keeps the image portable: a host with Mihomo TUN can route Claude,
GitHub, npm, and direct traffic with its own rules; a host without Mihomo uses
its normal network path. The project does not promise that every host can reach
Claude services. It preserves the host's policy boundary instead of embedding
one machine's proxy configuration.

`CLAUDE_CODE_CONTAINER_BUILD_NETWORK=host` applies only to `docker build`. It is
useful when package downloads must use the host network directly. Runtime
containers still use the Docker bridge.

## Daily workflow

```bash
# Enter the persistent environment.
claude-container

# Inspect prerequisites and managed resources.
claude-code-container doctor

# Update Claude Code inside the persistent Home volume.
claude update
```

The build requests the latest Claude Code release by default. Docker may reuse
the cached Claude installation layer during a rebuild, so `claude update`
inside the persistent environment is the direct way to refresh an existing
installation. Set `CLAUDE_CODE_CONTAINER_CLAUDE_VERSION` to an exact version when
reproducible builds matter more than receiving the latest release.

## Lifecycle

| Command | Image and integration | Persistent Home |
| --- | --- | --- |
| `claude-code-container install` | Build and initialize | Create or reuse |
| `claude-code-container reinstall` | Rebuild and repair | Preserve |
| `claude-code-container uninstall` | Remove | Preserve |
| `claude-code-container clear` | Remove | Delete after confirmation |
| `claude-code-container clear --yes` | Remove | Delete without prompting |

`reinstall` builds a replacement image before removing the current managed
runtime. `clear` is destructive: it removes Claude login state, user-installed
tools, container SSH material, and every other file in the named Home volume.

## Included toolbox

- Node.js, npm, Corepack, and pnpm
- Python, pip, and `venv`
- Git, curl, OpenSSH client, rsync, jq, ripgrep, and fd
- GCC, G++, make, pkg-config, and OpenSSL headers
- `ip`, `ifconfig`, `ping`, `dig`, `nc`, `lsof`, `ps`, and `pkill`
- Archive and file inspection utilities

The container user, UID, and GID are derived from the installing host user so
files created in `/workspace` retain the expected ownership.

## Configuration

The defaults are useful on a conventional Linux workstation. Override only the
parts owned by the local host:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CLAUDE_CODE_CONTAINER_IMAGE` | `claude-code-container:latest` | Managed Docker image |
| `CLAUDE_CODE_CONTAINER_HOME_VOLUME` | `claude-code-container-home` | Persistent Home volume |
| `CLAUDE_CODE_CONTAINER_WORKSPACE` | `~/work` | Host project directory |
| `CLAUDE_CODE_CONTAINER_DOCKERFILE` | `~/.local/share/claude-code-container/Dockerfile` | Build input |
| `CLAUDE_CODE_CONTAINER_TIMEZONE` | `UTC` | Container time zone |
| `CLAUDE_CODE_CONTAINER_CLAUDE_VERSION` | `latest` | Claude Code release or exact version |
| `CLAUDE_CODE_CONTAINER_BUILD_NETWORK` | unset | Optional Docker build network |
| `CLAUDE_CODE_CONTAINER_BASE_IMAGE` | pinned official Node image | Registry mirror with the same digest |
| `CLAUDE_CODE_CONTAINER_DEBIAN_MIRROR` | Debian official | Package mirror |
| `CLAUDE_CODE_CONTAINER_DEBIAN_SECURITY_MIRROR` | Debian official | Security package mirror |
| `CLAUDE_CODE_CONTAINER_SHELL_RC` | `~/.bashrc` | File receiving the managed alias |

Example for a host that needs local mirrors and host networking during build:

```bash
export CLAUDE_CODE_CONTAINER_TIMEZONE=America/Chicago
export CLAUDE_CODE_CONTAINER_BUILD_NETWORK=host
node_digest='sha256:f32b81066cde10a75dbac96646099533316d94bac4150c55da1636e1f0ffdc46'
export CLAUDE_CODE_CONTAINER_BASE_IMAGE="mirror.example/library/node@$node_digest"
export CLAUDE_CODE_CONTAINER_DEBIAN_MIRROR='https://mirror.example/debian'
export CLAUDE_CODE_CONTAINER_DEBIAN_SECURITY_MIRROR='https://mirror.example/debian-security'

claude-code-container install
```

## Security boundary

- No Docker socket, host private key, host Home, GPU, or privileged mode is
  mounted.
- No ports are published and no credentials or proxy configuration are baked
  into the image.
- The container generates its own Ed25519 key inside the persistent Home
  volume. The host authorization is limited to the Docker bridge subnet and
  disables agent, port, X11, and user-rc forwarding.
- Managed containers carry a volume-specific label so lifecycle cleanup does
  not select unrelated containers.
- `ssh host` grants the same shell privileges as the installing host user. The
  source and forwarding restrictions do **not** make that access read-only.

Read [SECURITY.md](./SECURITY.md) before exposing the environment to untrusted
code.

## Development

```bash
shellcheck bin/claude-code-container install.sh tests/test.sh
./tests/test.sh
```

CI runs the same ShellCheck and installer tests on every push and pull request.

## License

[MIT](./LICENSE)
