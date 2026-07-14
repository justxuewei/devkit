#!/bin/bash
#
# Update the kata guest rootfs image in place: swap in a freshly built
# kata-agent binary. The image path is read from the kata configuration (the
# active, non-commented `image =` line) so it always tracks whatever the config
# points at -- nothing is hardcoded.
#
# Unlike the RunD variant, this does NOT touch oam-agent / ilogtail units; kata
# ships its own guest agents. Only the kata-agent binary is replaced.
#
# Usage:
#   # default: install the musl-release kata-agent from the kata checkout
#   ./kata-update-guest-image.sh
#
#   # explicit binary / config:
#   KATA_AGENT_SRC=/path/to/kata-agent \
#   KATA_CONFIG=/etc/kata-containers/runtime-rs/configuration.db.toml \
#     ./kata-update-guest-image.sh
#
# Env overrides:
#   KATA_CONFIG      config to read the active `image =` from
#                    (default /etc/kata-containers/runtime-rs/configuration.db.toml)
#   KATA_AGENT_SRC   host-side kata-agent binary to install
#                    (default <kata repo>/target/x86_64-unknown-linux-musl/release/kata-agent)
#   MOUNT            mount point (default /mnt/disk)
#
# Build the agent first:  (in the kata repo)  just build ag   # make SECCOMP=no

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KATA_REPO="${KATA_REPO:-$HOME/developer/kata-containers}"

KATA_CONFIG="${KATA_CONFIG:-/etc/kata-containers/runtime-rs/configuration.db.toml}"
KATA_AGENT_SRC="${KATA_AGENT_SRC:-$KATA_REPO/target/x86_64-unknown-linux-musl/release/kata-agent}"
MOUNT="${MOUNT:-/mnt/disk}"

KATA_AGENT_DST="usr/bin/kata-agent"

log() { echo "[kata-update-guest-image] $*"; }
die() { echo "[kata-update-guest-image] ERROR: $*" >&2; exit 1; }

[ -f "$KATA_CONFIG" ]    || die "config not found: $KATA_CONFIG"
[ -f "$KATA_AGENT_SRC" ] || die "kata-agent not found: $KATA_AGENT_SRC (build it: 'just build ag')"
[ -f "$HERE/mount-image.sh" ]  || die "missing $HERE/mount-image.sh"
[ -f "$HERE/umount-image.sh" ] || die "missing $HERE/umount-image.sh"

# --- 1. resolve the ACTIVE image from the config -----------------------------
# Active line: `image = "..."`. Commented `#image = ...` lines are skipped by
# the leading-`image` anchor. Always read it fresh (never hardcode).
IMAGE="$(grep -E '^[[:space:]]*image[[:space:]]*=' "$KATA_CONFIG" \
  | head -1 \
  | sed -E 's/^[[:space:]]*image[[:space:]]*=[[:space:]]*//; s/^"//; s/".*$//; s/[[:space:]]*$//')"
[ -n "$IMAGE" ] || die "no active 'image =' line in $KATA_CONFIG"
[ -f "$IMAGE" ] || die "image file does not exist: $IMAGE"
log "active image: $IMAGE"
log "kata-agent:   $KATA_AGENT_SRC"

# --- 2. mount ----------------------------------------------------------------
# mount-image.sh echoes the loop device on its last stdout line and mounts p1 at
# $MOUNT. Capture the loop dev for the matching unmount.
MOUNT_OUT="$(sudo bash "$HERE/mount-image.sh" "$IMAGE" 2>&1)" || {
  echo "$MOUNT_OUT" >&2
  die "mount-image.sh failed (already mounted? stop running sandboxes, or: sudo bash $HERE/umount-image.sh <loopdev>)"
}
DEV="$(printf '%s\n' "$MOUNT_OUT" | grep -oE '/dev/loop[0-9]+' | tail -1)"
[ -n "$DEV" ] || die "could not determine loop device from mount-image.sh output"
log "mounted at $MOUNT via $DEV"

cleanup() {
  log "unmounting $DEV"
  sudo bash "$HERE/umount-image.sh" "$DEV" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mountpoint -q "$MOUNT" || die "$MOUNT is not a mountpoint after mount-image.sh"

# --- 3. install the kata-agent -----------------------------------------------
sudo install -D -m 0755 "$KATA_AGENT_SRC" "$MOUNT/$KATA_AGENT_DST"
log "installed kata-agent -> /$KATA_AGENT_DST"

sudo sync
log "done -- image updated: $IMAGE"
log "NOTE: regenerate any VM template (it snapshots the running guest agent)"
