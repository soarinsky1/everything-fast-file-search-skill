# Security

This skill only searches local filesystem metadata exposed through Everything and optionally reads selected candidate files for lightweight identity metadata such as size and SHA-256.

## Safety principles

- Do not broaden a user-scoped search without a reason.
- Do not recursively scan an entire drive as an automatic fallback.
- Do not terminate or restart an already-running Everything process solely to recover IPC.
- Do not install software or alter Windows startup configuration automatically.
- Treat search results as candidate paths, not trusted semantic identities.

If you discover a security issue in this repository, report it privately to the repository owner rather than posting sensitive details in a public issue.
