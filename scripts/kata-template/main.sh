#!/bin/bash
export LANG=""

# Kata (upstream, runtime-rs + dragonball) VM template dev helper.
#
# Subcommands:
#   create   - create the VM template: BootToBeTemplate config + a throwaway
#              nerdctl container; the template is dumped at sandbox boot
#   run      - start a pod from the template via crictl (BootFromTemplate)
#   run-cold - start a pod with the plain dragonball config (no template), baseline
#   status   - show active config, template files and kata pods
#   clean    - remove script-created pods/containers + template files, restore config
#
# Usage: bash main.sh {create|run|run-cold|status|clean}
#
# Modeled on ~/developer/devkit-ant/scripts/rund-template/main.sh, adapted for
# upstream kata:
#   - RunD selects configs per-pod via the rund-env annotation; the upstream
#     runtime-rs shim loads /etc/kata-containers/runtime-rs/configuration.toml
#     (a symlink), so this script forks configuration.db.toml per mode and
#     repoints the symlink. `clean` restores the original target.
#   - RunD uses boot_type = "BootToBeTemplate"/"BootFromTemplate" + template_path;
#     upstream kata uses the flattened [hypervisor.dragonball] keys
#     boot_to_be_template / boot_from_template / memory_path / device_state_path.
#   - Template creation: sandbox boot with boot_to_be_template=true dumps the
#     snapshot right after the guest sandbox is created (same semantics as RunD's
#     "template dumped at sandbox boot"), then the throwaway container is removed.
#     The snapshot is taken with branch semantics: the source VM is paused for
#     the capture and resumed, so the create container exits normally.
#
# Prereqs: /usr/local/bin/containerd-shim-kata-v2 is a symlink into the repo's
# musl debug build (src/runtime-rs/target/x86_64-unknown-linux-musl/debug/).
# Build the shim yourself with the dragonball snapshot changes; the symlink
# picks it up -- there is no install step here.

set -o pipefail

# ---- config (paths) ---------------------------------------------------------
KATA_ETC="/etc/kata-containers"
RRS_DIR="$KATA_ETC/runtime-rs"
BASE_CONFIG="$RRS_DIR/configuration.db.toml"          # dragonball base config
CREATE_CONFIG="$RRS_DIR/configuration.db.template-create.toml"
RUN_CONFIG="$RRS_DIR/configuration.db.template-run.toml"
ACTIVE_LINK="$RRS_DIR/configuration.toml"             # what the shim actually loads
ORIG_LINK_FILE="$RRS_DIR/.kata-template.orig-link"    # saved original symlink target

TEMPLATE_PATH="${TEMPLATE_PATH:-/run/vc/vm/template}" # memory + state live here
MEMORY_FILE="$TEMPLATE_PATH/memory"
STATE_FILE="$TEMPLATE_PATH/state"

IMAGE="${IMAGE:-docker.io/library/busybox:latest}"
CMD="${CMD:-ip a}"                                    # in-container command
RUNTIME_CRI="kata"                                    # containerd CRI handler name
RUNTIME_NERDCTL="io.containerd.kata.v2"               # nerdctl runtime type

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNDIR="$WORKDIR/run"                                 # crictl json + pod/ctr ids

# ---- helpers ----------------------------------------------------------------
die() { echo "Error: $*" >&2; exit 1; }

# Everything below needs root (containerd sock, /etc writes, /run/vc).
[ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" "$@"

# set_toml_key <file> <section> <key> <value>
# Ensure `key = value` under [section]: replaces an existing (even commented) key
# in that section, else inserts after the header, else appends the section at EOF.
set_toml_key() {
    local file="$1" section="[$2]" key="$3" value="$4" tmp
    tmp="$(mktemp)"
    awk -v section="$section" -v key="$key" -v value="$value" '
        function trim(s){ sub(/^[ \t]+/,"",s); sub(/[ \t]+$/,"",s); return s }
        BEGIN { insec=0; done=0 }
        {
            t = trim($0)
            if (t ~ /^\[/) {
                if (insec && !done) { print key " = " value; done=1 }
                insec = (t == section)
                print; next
            }
            if (insec && !done && t ~ ("^#?[ \t]*" key "[ \t]*=")) {
                print key " = " value; done=1; next
            }
            print
        }
        END {
            if (insec && !done) { print key " = " value; done=1 }
            if (!done) { print ""; print section; print key " = " value }
        }
    ' "$file" > "$tmp" && /usr/bin/cp -f "$tmp" "$file"
    rm -f "$tmp"
}

# Remember the original symlink target once, so clean can restore it.
save_orig_link() {
    if [ ! -f "$ORIG_LINK_FILE" ]; then
        readlink "$ACTIVE_LINK" > "$ORIG_LINK_FILE" 2>/dev/null || echo "" > "$ORIG_LINK_FILE"
    fi
}

# point_config <path> - make the shim load <path>
point_config() {
    save_orig_link
    ln -sfn "$1" "$ACTIVE_LINK"
    echo "shim config -> $(readlink "$ACTIVE_LINK")"
}

# ensure_config <create|run> -> prints config path
# Forks the dragonball base config and sets the flattened vm_template keys.
ensure_config() {
    local mode="$1" cfg
    [ -f "$BASE_CONFIG" ] || die "base config not found: $BASE_CONFIG"
    case "$mode" in
        create) cfg="$CREATE_CONFIG" ;;
        run)    cfg="$RUN_CONFIG" ;;
        *)      die "ensure_config: bad mode $mode" ;;
    esac
    /usr/bin/cp -f "$BASE_CONFIG" "$cfg"
    # VmTemplateInfo is #[serde(flatten)] -> keys live directly under
    # [hypervisor.dragonball].
    if [ "$mode" = "create" ]; then
        set_toml_key "$cfg" "hypervisor.dragonball" "boot_to_be_template" "true"
        set_toml_key "$cfg" "hypervisor.dragonball" "boot_from_template"  "false"
    else
        set_toml_key "$cfg" "hypervisor.dragonball" "boot_to_be_template" "false"
        set_toml_key "$cfg" "hypervisor.dragonball" "boot_from_template"  "true"
    fi
    set_toml_key "$cfg" "hypervisor.dragonball" "memory_path"       "\"$MEMORY_FILE\""
    set_toml_key "$cfg" "hypervisor.dragonball" "device_state_path" "\"$STATE_FILE\""
    # Snapshot support covers the MMIO virtio transport only; the base config
    # uses virtio-blk-pci for the VM rootfs, which save_states refuses
    # (InvalidBlockDeviceType). Force MMIO on both sides.
    set_toml_key "$cfg" "hypervisor.dragonball" "vm_rootfs_driver" "\"virtio-blk-mmio\""
    # The template and the restored pod must have IDENTICAL device sets in
    # identical order: guest-visible MMIO windows are assigned by insertion
    # order, so an extra device (e.g. the CNI virtio-net the run pod would
    # get) shifts every later device and the restored guest talks to the
    # wrong addresses. Disable pod networking on both sides.
    set_toml_key "$cfg" "runtime" "internetworking_model" "\"none\""
    set_toml_key "$cfg" "runtime" "disable_new_netns" "true"
    echo "$cfg"
}

show_template_keys() {
    grep -nE "boot_to_be_template|boot_from_template|memory_path|device_state_path" "$1" || true
}

# ---- subcommands ------------------------------------------------------------
cmd_create() {
    echo "=== [1/3] BootToBeTemplate config ==="
    local cfg name
    cfg="$(ensure_config create)" || exit 1
    show_template_keys "$cfg"
    point_config "$cfg"

    echo "=== [2/3] creating template into $TEMPLATE_PATH ==="
    mkdir -p "$TEMPLATE_PATH"
    rm -f "$MEMORY_FILE" "$STATE_FILE"
    name="kata-template-create-$$"
    nerdctl pull "$IMAGE" >/dev/null 2>&1 || echo "warn: nerdctl pull failed, assuming image present"
    # The template is dumped when the sandbox finishes booting (agent up,
    # guest sandbox created), independent of the container workload. The
    # container run may still exit non-zero -> don't abort; verify the files.
    nerdctl run --rm --runtime "$RUNTIME_NERDCTL" --net none --name "$name" \
        "$IMAGE" $CMD \
        || echo "nerdctl run exited non-zero -- template is dumped at sandbox boot, verifying"
    nerdctl rm -f "$name" >/dev/null 2>&1 || true

    echo "=== [3/3] verifying template files ==="
    if [ -s "$MEMORY_FILE" ] && [ -s "$STATE_FILE" ]; then
        ls -la "$TEMPLATE_PATH"
        echo "OK: template created."
    else
        die "template files missing/empty under $TEMPLATE_PATH -- check 'journalctl -t kata' / containerd logs"
    fi
}

cmd_run() {
    echo "=== [1/3] BootFromTemplate config ==="
    local cfg ts pod_json ctr_json pod cid
    cfg="$(ensure_config run)" || exit 1
    show_template_keys "$cfg"
    point_config "$cfg"
    if [ ! -s "$MEMORY_FILE" ] || [ ! -s "$STATE_FILE" ]; then
        echo "warn: no template under $TEMPLATE_PATH -- run 'bash main.sh create' first" >&2
    fi

    echo "=== [2/3] starting pod from template via crictl ==="
    mkdir -p "$RUNDIR"
    ts="$(date +%s)"
    pod_json="$RUNDIR/pod-$ts.json"
    ctr_json="$RUNDIR/ctr-$ts.json"
    cat > "$pod_json" <<EOF
{
    "metadata": {
        "name": "kata-template-pod-$ts",
        "namespace": "default",
        "uid": "kata-template-$ts",
        "attempt": 0
    },
    "log_directory": "/tmp/kata-template-logs",
    "linux": {}
}
EOF
    cat > "$ctr_json" <<EOF
{
    "metadata": { "name": "kata-template-ctr" },
    "image": { "image": "$IMAGE" },
    "command": ["sh", "-c", "$CMD; sleep 3600"],
    "log_path": "kata-template-ctr-$ts.log",
    "linux": {}
}
EOF
    mkdir -p /tmp/kata-template-logs
    crictl pull "$IMAGE" >/dev/null 2>&1 || echo "warn: crictl pull failed, assuming image present"
    pod="$(crictl runp --runtime "$RUNTIME_CRI" "$pod_json")" || die "crictl runp failed"
    echo "$pod" > "$RUNDIR/last-pod"
    echo "pod sandbox: $pod"
    cid="$(crictl create "$pod" "$ctr_json" "$pod_json")" || die "crictl create failed"
    echo "$cid" > "$RUNDIR/last-ctr"
    crictl start "$cid" || die "crictl start failed"

    echo "=== [3/3] result ==="
    crictl pods --id "$pod"
    crictl ps -a --pod "$pod"
    echo "container output: crictl logs $cid"
}

cmd_run_cold() {
    echo "=== cold start (plain $BASE_CONFIG, no template) ==="
    # Baseline for comparing against BootFromTemplate.
    [ -f "$BASE_CONFIG" ] || die "base config not found: $BASE_CONFIG"
    point_config "$BASE_CONFIG"
    local ts pod_json ctr_json pod cid
    mkdir -p "$RUNDIR"
    ts="$(date +%s)"
    pod_json="$RUNDIR/pod-cold-$ts.json"
    ctr_json="$RUNDIR/ctr-cold-$ts.json"
    cat > "$pod_json" <<EOF
{
    "metadata": {
        "name": "kata-cold-pod-$ts",
        "namespace": "default",
        "uid": "kata-cold-$ts",
        "attempt": 0
    },
    "log_directory": "/tmp/kata-template-logs",
    "linux": {}
}
EOF
    cat > "$ctr_json" <<EOF
{
    "metadata": { "name": "kata-cold-ctr" },
    "image": { "image": "$IMAGE" },
    "command": ["sh", "-c", "$CMD; sleep 3600"],
    "log_path": "kata-cold-ctr-$ts.log",
    "linux": {}
}
EOF
    mkdir -p /tmp/kata-template-logs
    crictl pull "$IMAGE" >/dev/null 2>&1 || echo "warn: crictl pull failed, assuming image present"
    pod="$(crictl runp --runtime "$RUNTIME_CRI" "$pod_json")" || die "crictl runp failed"
    cid="$(crictl create "$pod" "$ctr_json" "$pod_json")" || die "crictl create failed"
    crictl start "$cid" || die "crictl start failed"
    crictl pods --id "$pod"
    echo "container output: crictl logs $cid"
}

cmd_status() {
    echo "=== shim config ==="
    ls -la "$ACTIVE_LINK"
    echo "=== template files ($TEMPLATE_PATH) ==="
    ls -la "$TEMPLATE_PATH" 2>/dev/null || echo "(none)"
    echo "=== kata pods ==="
    crictl pods 2>/dev/null | head -10
    echo "=== nerdctl containers ==="
    nerdctl ps -a 2>/dev/null | grep -E "kata-template|CONTAINER" | head -5
}

cmd_clean() {
    echo "=== removing script-created pods/containers ==="
    local pod
    for pod in $(crictl pods -q --name kata-template-pod 2>/dev/null) \
               $(crictl pods -q --name kata-cold-pod 2>/dev/null); do
        crictl stopp "$pod" >/dev/null 2>&1
        crictl rmp "$pod" >/dev/null 2>&1 && echo "removed pod $pod"
    done
    nerdctl rm -f "$(nerdctl ps -aq --filter name=kata-template-create 2>/dev/null)" >/dev/null 2>&1
    echo "=== removing template files ==="
    rm -f "$MEMORY_FILE" "$STATE_FILE" && echo "removed $MEMORY_FILE, $STATE_FILE"
    echo "=== restoring original shim config ==="
    if [ -f "$ORIG_LINK_FILE" ] && [ -s "$ORIG_LINK_FILE" ]; then
        ln -sfn "$(cat "$ORIG_LINK_FILE")" "$ACTIVE_LINK"
        rm -f "$ORIG_LINK_FILE"
        echo "shim config -> $(readlink "$ACTIVE_LINK")"
    else
        echo "no saved original config link; leaving $ACTIVE_LINK as-is"
    fi
    rm -rf "$RUNDIR"
}

# ---- dispatch ---------------------------------------------------------------
case "${1:-}" in
    create)   cmd_create ;;
    run)      cmd_run ;;
    run-cold) cmd_run_cold ;;
    status)   cmd_status ;;
    clean)    cmd_clean ;;
    *)
        echo "Usage: bash $0 {create|run|run-cold|status|clean}"
        echo "  create    create the VM template (BootToBeTemplate, via nerdctl)"
        echo "  run       start a pod from the template (BootFromTemplate, via crictl)"
        echo "  run-cold  start a pod with the plain dragonball config (baseline)"
        echo "  status    show active config, template files and kata pods"
        echo "  clean     remove pods/template files, restore original config"
        exit 1 ;;
esac
