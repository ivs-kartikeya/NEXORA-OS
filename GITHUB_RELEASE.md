# Publishing Nexora OS V1 on GitHub

The ISO should be distributed as a **GitHub Release asset**, not committed into the Git repository.

1. Build and test the live image:

```bash
./iso/build-iso.sh
```

2. Create/push your normal source repository.
3. Install/login to GitHub CLI (`gh auth login`).
4. From the repository checkout:

```bash
./scripts/publish-github-release.sh
```

This creates the prerelease tag `v1.0.1-beta.1` and uploads:

- `NexoraOS-1.0.1-beta.1-amd64.iso`
- its SHA-256 checksum

Do not use a normal `git add` for the ISO.
