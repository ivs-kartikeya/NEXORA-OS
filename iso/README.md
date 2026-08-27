# Nexora OS V1 Public Beta ISO

`./iso/build-iso.sh` builds an **amd64 bootable live testing image** using Debian `live-build`.

The V1 beta ISO is intended for VMware/VirtualBox and early hardware testing. It is deliberately a live image, not the production disk installer yet.

Before building, V1 expects Tony and Voice to be prepared on the build machine:

```bash
./scripts/setup-tony.sh fast
./scripts/setup-voice.sh
./iso/build-iso.sh
```

Output:

```text
dist/NexoraOS-1.0.1-beta.1-amd64.iso
dist/NexoraOS-1.0.1-beta.1-amd64.iso.sha256
```

Always boot the generated image in a brand-new VM before publishing it.
