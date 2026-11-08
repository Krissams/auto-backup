# Security policy

## Reporting a vulnerability

Please use GitHub's [private vulnerability reporting](https://github.com/Krissams/auto-backup/security/advisories/new) for security issues, especially unintended file access, writing outside a selected destination, or exposing private file data. Do not publish exploit details or sensitive files in a public issue.

Include the affected commit or version, macOS version, a concise description, and reproduction steps using disposable example files where possible. Redact credentials, personal filenames, and private paths. The maintainer will review reports as capacity allows; no response-time commitment is currently offered.

Ordinary bugs and feature requests belong in [issues](https://github.com/Krissams/auto-backup/issues/new/choose).

## Supported code

Security fixes are developed on the current `main` branch. There is not yet a separate long-term-support release policy. Source builds and CI artifacts are locally signed for testing and are not Apple-notarized releases.

## Data handling

The application works with the local folders you select. It does not upload your files or include analytics. Selected source and destination paths and the backup-folder name are stored in local macOS preferences. Error messages and screenshots can contain file paths; review them before sharing.
