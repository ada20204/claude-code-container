# Run containerized Claude Code with Herdr

This guide connects Herdr to Claude Code without installing Herdr or an SSH
server inside the container. Herdr stays on the host, where it can identify and
control the terminal process. Claude Code runs in the disposable development
container with its persistent Home volume and host-mounted projects.

## Architecture

```text
Herdr client
  -> SSH
  -> Herdr server on the development host
  -> claude-herdr host wrapper
  -> claude-code-container run --cwd ...
  -> Claude Code inside the container
```

The host wrapper is important. Setting `HERDR_AGENT=claude` only inside the
container hides that marker from the host process tree that Herdr observes.
Running Herdr or SSHD inside the container would add another control plane and
is unnecessary for this integration.

## Prerequisites

- `claude-code-container` is installed on the development host.
- Herdr is installed and its server is running on the development host.
- The controlling machine can connect to the development host with SSH public
  key authentication.
- The project directory is covered by a standard, extra, or custom container
  mount.

Verify the local components on the development host:

```bash
herdr --version
herdr status server
"$HOME/.local/share/claude-code-container/claude-code-container" doctor
```

## Install the host wrapper

Create `~/.local/bin/claude-herdr` on the development host:

```bash
install -d "$HOME/.local/bin"
cat >"$HOME/.local/bin/claude-herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

launcher="${CLAUDE_CODE_CONTAINER_LAUNCHER:-$HOME/.local/share/claude-code-container/claude-code-container}"
export HERDR_AGENT=claude
exec "$launcher" run --cwd "$PWD" -- claude "$@"
EOF
chmod 755 "$HOME/.local/bin/claude-herdr"
```

Ensure `~/.local/bin` is in the interactive shell's `PATH`, then verify the
wrapper without starting an interactive session:

```bash
command -v claude-herdr
claude-herdr --version
```

## Preserve the project directory

The wrapper passes the host's current directory to `run --cwd`. The launcher
maps that directory to the corresponding container mount target before setting
Docker's working directory.

The standard workspace mapping behaves as follows:

```text
Host:      ~/work/example
Container: /workspace/example
```

A same-path custom mount keeps its absolute path:

```bash
export CLAUDE_CODE_CONTAINER_MOUNTS="$HOME/mywork:$HOME/mywork"
cd "$HOME/mywork/example"
claude-herdr --resume
```

In this example, Claude Code starts in `~/mywork/example` inside the container.
If the current host directory is not covered by a container mount, the launcher
stops with an error instead of silently starting in the container Home.

## Add the development host to another Herdr machine

First create an SSH alias on the controlling machine. The alias should use
public key authentication and should reach the account that runs the remote
Herdr server:

```sshconfig
Host development-host
    HostName development-host.example.net
    User developer
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

Verify SSH before involving Herdr:

```bash
ssh -o BatchMode=yes development-host 'hostname'
```

Register the machine with Herdr:

```bash
herdr machine add \
  --label "Development host" \
  --remote-session default \
  development-host
```

Open the remote Herdr session from the controlling machine:

```bash
herdr --remote development-host --session default
```

Inside a pane on the development host, start Claude Code from the intended
project directory:

```bash
cd ~/work/example
claude-herdr --resume
```

Herdr can now identify the host pane as a Claude agent while the actual Claude
process and development tools remain inside the container.

## Verify the integration

Run these checks from the development host:

```bash
cd ~/work/example
"$HOME/.local/share/claude-code-container/claude-code-container" \
  run --cwd "$PWD" -- pwd
claude-herdr --version
```

The first command should print `/workspace/example`. In a Herdr session, start
`claude-herdr`, then inspect the registered agents from another pane:

```bash
herdr agent list
```

## Troubleshooting

### Claude starts in Home

Confirm the wrapper includes both `--cwd "$PWD"` and the argument separator
before `claude`:

```bash
exec "$launcher" run --cwd "$PWD" -- claude "$@"
```

Also confirm that the deployed launcher supports `run --cwd`.

### The directory is not covered by a mount

Add the directory through `CLAUDE_CODE_CONTAINER_EXTRA_HOME_DIRS` or
`CLAUDE_CODE_CONTAINER_MOUNTS`. The environment variables are inherited by the
host wrapper, so a one-off invocation can declare a mount without changing the
script:

```bash
CLAUDE_CODE_CONTAINER_MOUNTS="$HOME/project:$HOME/project" claude-herdr
```

Do not mount the entire host Home directory merely to avoid declaring the
required project path.

### Herdr does not identify the pane as Claude

Start Claude with `claude-herdr`, not by running `claude` directly inside an
unmarked container shell. Confirm that `HERDR_AGENT=claude` is exported by the
host wrapper and that the Herdr server is running on the same host.

### The remote machine is saved but unavailable

Test `ssh -o BatchMode=yes <target> hostname` from the controlling machine.
Then verify `herdr status server` on the development host. Herdr registration
does not repair SSH authentication, routing, or a stopped remote server.

## Security boundary

- Herdr and SSH remain host services; the container does not expose an SSH
  port.
- The wrapper grants no additional container privileges or mounts.
- `--cwd` accepts only directories covered by declared mounts.
- Existing `ssh host` access from the container keeps the restrictions
  installed by `claude-code-container`.
- Anyone able to control the remote Herdr session can operate Claude Code with
  the permissions of the remote host account and its configured container
  mounts.
