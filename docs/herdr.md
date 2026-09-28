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

- `claude-code-container` and the desired numbered instance are initialized
  on the development host; follow the [README quick start](../README.md#start-here).
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

On the development host, run from the `claude-code-container` repository
checkout. Install the maintained script instead of creating another copy of
its implementation:

```bash
install -d "$HOME/.local/bin"
install -m 0755 ./bin/claude-herdr "$HOME/.local/bin/claude-herdr"
```

The base `install.sh` does not install this optional wrapper. Repeat the copy
after updating the checkout. No extra entry is needed for each instance.
Ensure `~/.local/bin` is already on the host shell's `PATH`, or use the full
`~/.local/bin/claude-herdr` path. Neither installer adds this directory to PATH.
If the launcher was installed under a custom `XDG_DATA_HOME`, export
`CLAUDE_CODE_CONTAINER_LAUNCHER` with its actual absolute path before using
the wrapper.

On the host, verify from a mounted directory without opening an interactive
Claude conversation (this still initializes and starts a disposable container):

```bash
command -v claude-herdr
cd ~/work
claude-herdr 1 --version
```

Use `claude-herdr N [CLAUDE_ARGS...]` to select an instance; omitting `N` selects
`1`. `--instance N` is also accepted. All remaining arguments go to Claude,
so `claude-herdr --help` shows Claude's help, not container maintenance help.
For installation or cleanup, use the full lifecycle launcher path described
in the README. The wrapper does not install or start the Herdr server.

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
claude-herdr 2 --resume
```

In this example, Claude Code starts in `~/mywork/example` inside the container.
If the current host directory is not covered by a container mount, the launcher
stops with an error instead of silently starting in the container Home.
Omit `--resume` for a new conversation. On first use of an instance, complete
its Claude sign-in prompts. `claude-container N` instead opens a shell in Home;
it does not preserve the host project directory.

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
claude-herdr 1 --resume
```

Herdr can now identify the host pane as a Claude agent while the actual Claude
process and development tools remain inside the numbered container. Register
the Host once; use a different Herdr pane or session for each instance.

## Verify the integration

Run these checks from the development host:

```bash
cd ~/work/example
"$HOME/.local/share/claude-code-container/claude-code-container" \
  --instance 1 run --cwd "$PWD" -- pwd
claude-herdr 1 --version
```

The first command should print `/workspace/example`. In a Herdr session, start
`claude-herdr 1`, then inspect the registered agents from another pane:

```bash
herdr agent list
```

## Troubleshooting

### Claude starts in Home

Check `command -v claude-herdr`, then reinstall `bin/claude-herdr` using the
copy command above. The maintained wrapper passes `--instance`, `--cwd "$PWD"`,
and `-- claude` to the launcher. Also confirm that the deployed launcher
supports `run --cwd`; update it with `./install.sh` from the same checkout.

### The directory is not covered by a mount

Add the directory through `CLAUDE_CODE_CONTAINER_EXTRA_HOME_DIRS` or
`CLAUDE_CODE_CONTAINER_MOUNTS`. The environment variables are inherited by the
host wrapper, so a one-off invocation can declare a mount without changing the
script:

```bash
CLAUDE_CODE_CONTAINER_MOUNTS="$HOME/project:$HOME/project" claude-herdr 1
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
