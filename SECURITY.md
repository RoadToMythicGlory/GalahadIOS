# Security

## Reporting a vulnerability

If you discover a security issue in Galahad iOS, **do not open a public issue**.

Contact the maintainers privately (repository admins).
Include steps to reproduce, affected versions/builds, and impact.

## Scope notes

- SRT caller destinations and control WebSocket URLs are operator-configured;
  treat them as trusted network endpoints in deployment.
- App Group `group.gg.galahad.ios` holds config/status shared with the Broadcast
  Upload Extension — protect device signing and provisioning accordingly.
- Secrets (App Store Connect API keys, Codemagic integrations, signing certs)
  must never be committed. Use Codemagic / GitHub encrypted secrets only.
