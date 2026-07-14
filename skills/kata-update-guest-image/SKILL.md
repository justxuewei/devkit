---
name: kata-update-guest-image
description: Update the kata guest rootfs image in place — mount the image referenced by the active kata config, install a freshly built kata-agent binary, and unmount. Use after rebuilding the agent (`just build ag` in the kata repo) to get it into the VM image. Self-contained: bundles its own mount/umount helpers. Kata-only (no oam-agent/ilogtail, unlike the RunD variant).
---

# kata-update-guest-image

Mounts the kata guest rootfs image, swaps in a new `kata-agent` binary, then
unmounts — driven by `kata-update-guest-image.sh`. The image path is **read
from the kata config at run time** (the active, non-commented `image =` line),
so it always follows whatever the config points at; nothing is hardcoded.

This is the kata counterpart of the RunD `update-guest-image` skill. The only
guest-side difference that matters here: kata ships its own agents, so this
skill **only** replaces `usr/bin/kata-agent` and does not create/modify any
oam-agent or ilogtail units.

## Inputs / assumptions

- Config: `/etc/kata-containers/runtime-rs/configuration.db.toml`
  (override with `KATA_CONFIG`). The active image is the single `image = "..."`
  line that is **not** commented (`#image = ...` lines are ignored).
- Agent binary: `<kata repo>/target/x86_64-unknown-linux-musl/release/kata-agent`
  (override with `KATA_AGENT_SRC`; repo root via `KATA_REPO`, default
  `~/developer/kata-containers`).
- Mount helpers: `mount-image.sh` / `umount-image.sh` **in this directory**
  (copied from `~/kata3`), so the skill is self-contained. They mount partition
  1 at `/mnt/disk` and echo the loop device.
- Mount point: `/mnt/disk` (override with `MOUNT`).

## Usage

```bash
cd ~/developer/devkit/skills/kata-update-guest-image

# 1. build the agent (in the kata repo)
#    just build ag              # == make SECCOMP=no, outputs the musl-release binary

# 2. default: install that musl-release kata-agent into the active image
./kata-update-guest-image.sh

# explicit binary / config:
KATA_AGENT_SRC=/path/to/kata-agent \
KATA_CONFIG=/etc/kata-containers/runtime-rs/configuration.db.toml \
  ./kata-update-guest-image.sh
```

## What the script does

1. Read the active `image =` from the config.
2. `mount-image.sh <image>` → mount p1 at `/mnt/disk`, capture the loop device.
3. `install -m0755` the agent to `usr/bin/kata-agent`.
4. `sync`, then `umount-image.sh <loopdev>` (always, via an EXIT trap).

## Notes

- Requires `sudo` (loop mount + writing into the image).
- **Stop running sandboxes first** — the image can't be looped while in use.
  If it's already mounted the script reports it; unmount with
  `sudo bash ./umount-image.sh <loopdev>`.
- Edits the image **in place** — the next VM boot picks up the new agent.
- **Regenerate any VM template afterwards.** A template snapshots the *running*
  guest agent into guest RAM, so an existing template still carries the old
  agent until you rebuild it (e.g. `bash .../kata-template/main.sh create`).
