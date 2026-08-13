# claude-code-dev

A disposable Linux development container for Claude Code with a persistent
Home volume, a host workspace mount, and restricted container-to-host SSH.

## Why

The container can be rebuilt freely while Claude login state, user-installed
tools, SSH configuration, and `~/.claude/CLAUDE.md` remain in a named Docker
volume. Projects stay on the host under `~/work` and are available as both
`/workspace` and `~/work` inside the container.

## Requirements

- Linux on `amd64` or `arm64`
- Docker Engine usable without `sudo`
- Bash, Python 3, OpenSSH server, and a writable `~/.ssh/authorized_keys`
- A host workspace at `~/work`, or `CLAUDE_CODE_DEV_WORKSPACE`

## Install

```bash
git clone https://github.com/ada20204/claude-code-dev.git
cd claude-code-dev
./install.sh
claude-code-dev install
source ~/.bashrc
```

Enter the environment:

```bash
claude-dev
```

Inside the container:

```bash
ssh host
```

The generated host key is stored only in the persistent Home volume. Its
authorization is restricted to the current Docker bridge subnet and disables
agent, port, X11, and user-rc forwarding.

Installation fails rather than replacing an existing `Host host`,
`claude-dev` alias, or `~/work` path. It also verifies a real BatchMode SSH
connection before reporting success.

## Lifecycle

```bash
claude-code-dev install
claude-code-dev reinstall
claude-code-dev uninstall
claude-code-dev clear
claude-code-dev clear --yes
claude-code-dev doctor
```

`reinstall` preserves the Home volume. `uninstall` removes the managed image,
alias, host authorization, and related containers while preserving Home data.
`clear` also removes the Home volume and therefore requires confirmation.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `CLAUDE_CODE_DEV_IMAGE` | `claude-code-dev:latest` | Docker image name |
| `CLAUDE_CODE_DEV_HOME_VOLUME` | `claude-code-dev-home` | Persistent Home volume |
| `CLAUDE_CODE_DEV_WORKSPACE` | `~/work` | Host project directory |
| `CLAUDE_CODE_DEV_DOCKERFILE` | `~/.local/share/claude-code-dev/Dockerfile` | Build input |
| `CLAUDE_CODE_DEV_TIMEZONE` | `UTC` | Container time zone |
| `CLAUDE_CODE_DEV_CLAUDE_VERSION` | `2.1.228` | Reproducible Claude Code baseline |
| `CLAUDE_CODE_DEV_BUILD_NETWORK` | unset | Optional Docker build network, such as `host` |
| `CLAUDE_CODE_DEV_BASE_IMAGE` | Pinned official Node image | Optional registry mirror while preserving a pinned digest |
| `CLAUDE_CODE_DEV_DEBIAN_MIRROR` | Debian official | Optional Debian package mirror |
| `CLAUDE_CODE_DEV_DEBIAN_SECURITY_MIRROR` | Debian official | Optional Debian security mirror |
| `CLAUDE_CODE_DEV_SHELL_RC` | `~/.bashrc` | Shell file containing the managed `claude-dev` alias |

Example:

```bash
export CLAUDE_CODE_DEV_TIMEZONE=America/Chicago
export CLAUDE_CODE_DEV_WORKSPACE=$HOME/projects
export CLAUDE_CODE_DEV_BUILD_NETWORK=host
export CLAUDE_CODE_DEV_BASE_IMAGE='mirror.example/library/node@sha256:f32b81066cde10a75dbac96646099533316d94bac4150c55da1636e1f0ffdc46'
claude-code-dev install
```

## Included tools

Node.js, npm, pnpm, Python, Git, curl, OpenSSH client, GCC/G++, make, jq,
rsync, ripgrep, fd, and common network/process diagnostics.

Run `claude update` inside the container to update Claude Code independently of
the image baseline. The update remains in the persistent Home volume.

## Security model

- No Docker socket, host private key, host Home, GPU, or privileged mode is mounted.
- Containers are disposable and carry a project-specific Docker label.
- Lifecycle cleanup selects only containers with that label.
- No ports are published.
- The image contains no credentials or proxy configuration.
- `ssh host` grants the container the same shell privileges as the installing
  host user; the source and forwarding restrictions do not make that access
  read-only.
- `clear --yes` is destructive and removes Claude login state.

## Development

```bash
bash -n bin/claude-code-dev install.sh tests/test.sh
./tests/test.sh
```

See [SECURITY.md](SECURITY.md) for reporting security issues.
