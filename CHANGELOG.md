# Changelog

## 1.0.0 — 2026-10-11

First release. Actual Budget's server in Container Manager, on HTTPS from the
start: DSM's certificate, or a self-signed one when there isn't one. Plain
HTTP is allowed only behind DSM's reverse proxy. The server password is set at
the first start and shown once.

The DSM window adds:
- **Budgets:** each budget's size, last sync, and whether it's encrypted or
  deleted; the devices signed in; a DSM notification when syncing goes quiet;
  and the upload size limit.
- **Sign-in:** a QR code for phones, a new password (optionally signing every
  device out), and sign every device out.

Also included: consistent backups, updates and removal.
