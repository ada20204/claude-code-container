# Security policy

Please do not open public issues for vulnerabilities. Use GitHub private
vulnerability reporting for this repository.

The project modifies `~/.ssh/authorized_keys` to grant a generated container
key restricted access from the Docker bridge subnet on Linux, or OrbStack's
forwarded loopback source on macOS. Review this behavior
before installation. On the host, use the installed lifecycle launcher to revoke
the selected instance's managed authorization:

```bash
"$HOME/.local/share/claude-code-container/claude-code-container" --instance 1 uninstall
```

Replace `uninstall` with `clear` to also delete its entire Home volume, including
the private key and Claude login state, after confirmation. Shared images,
shell entry points, other instances, and host-mounted files remain intact.
