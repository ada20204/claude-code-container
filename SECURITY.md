# Security policy

Please do not open public issues for vulnerabilities. Use GitHub private
vulnerability reporting for this repository.

The project modifies `~/.ssh/authorized_keys` to grant a generated container
key restricted access from the Docker bridge subnet. Review this behavior
before installation. Run `claude-code-container uninstall` to revoke the managed
authorization or `claude-code-container clear` to also destroy the private key.
