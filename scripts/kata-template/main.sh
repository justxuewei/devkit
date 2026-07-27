#!/bin/bash
export LANG=""

# Kata (upstream, runtime-rs + dragonball) VM template dev helper.
#
# Subcommands:
#   create   - create the VM template with kata-ctl factory init
#   run      - start a pod through the enabled VM factory
#   run-cold - start a pod with the plain dragonball config (no template), baseline
#   benchmark - compare three template restores with three cold starts
#   status   - show active config, template files and kata pods
#   clean    - remove script-created pods/containers + template files, restore config
#
# Usage: bash main.sh {create|run|run-cold|benchmark|status|clean}
#
# The runtime-rs shim loads /etc/kata-containers/runtime-rs/configuration.toml
# (a symlink), so this script forks configuration.db.toml per mode and repoints
# the symlink. Template creation and restore are selected only through
# [hypervisor.dragonball.factory]; the low-level boot_to/from_template keys are
# intentionally not written by this script.
#
# Prereqs: /usr/local/bin/containerd-shim-kata-v2 is a symlink into the repo's
# musl debug build (src/runtime-rs/target/x86_64-unknown-linux-musl/debug/).
# Build the shim and a Dragonball-enabled kata-ctl before running this script.

set -o pipefail

# ---- config (paths) ---------------------------------------------------------
KATA_ETC="/etc/kata-containers"
RRS_DIR="$KATA_ETC/runtime-rs"
BASE_CONFIG="$RRS_DIR/configuration.db.toml"          # dragonball base config
CREATE_CONFIG="$RRS_DIR/configuration.db.template-create.toml"
RUN_CONFIG="$RRS_DIR/configuration.db.template-run.toml"
COLD_CONFIG="$RRS_DIR/configuration.db.template-cold.toml"
ACTIVE_LINK="$RRS_DIR/configuration.toml"             # what the shim actually loads
ORIG_LINK_FILE="$RRS_DIR/.kata-template.orig-link"    # saved original symlink target

TEMPLATE_PATH="${TEMPLATE_PATH:-/run/vc/vm/template}" # memory + state live here
MEMORY_FILE="$TEMPLATE_PATH/memory"
STATE_FILE="$TEMPLATE_PATH/state"

IMAGE="${IMAGE:-docker.io/library/busybox:latest}"
CMD="${CMD:-ip a}"                                    # in-container command
RUNTIME_CRI="kata"                                    # containerd CRI handler name

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNDIR="$WORKDIR/run"                                 # crictl json + pod/ctr ids
KATA_REPO="$(cd "$WORKDIR/../../.." && pwd)/kata-containers"
KATA_CTL="${KATA_CTL:-$(command -v kata-ctl 2>/dev/null || true)}"
KATA_CTL="${KATA_CTL:-$KATA_REPO/target/x86_64-unknown-linux-musl/debug/kata-ctl}"

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

# ensure_config <create|run|cold> -> prints config path
# Forks the Dragonball base config and selects the common VM factory.
ensure_config() {
    local mode="$1" cfg
    [ -f "$BASE_CONFIG" ] || die "base config not found: $BASE_CONFIG"
    case "$mode" in
        create) cfg="$CREATE_CONFIG" ;;
        run)    cfg="$RUN_CONFIG" ;;
        cold)   cfg="$COLD_CONFIG" ;;
        *)      die "ensure_config: bad mode $mode" ;;
    esac
    /usr/bin/cp -f "$BASE_CONFIG" "$cfg"
    if [ "$mode" = "cold" ]; then
        set_toml_key "$cfg" "hypervisor.dragonball.factory" "enable_template" "false"
    else
        set_toml_key "$cfg" "hypervisor.dragonball.factory" "enable_template" "true"
    fi
    set_toml_key "$cfg" "hypervisor.dragonball.factory" \
        "template_path" "\"$TEMPLATE_PATH\""
    # Snapshot support covers the MMIO virtio transport only; the base config
    # uses virtio-blk-pci for the VM rootfs, which save_states refuses
    # (InvalidBlockDeviceType). Force MMIO on both sides.
    set_toml_key "$cfg" "hypervisor.dragonball" "vm_rootfs_driver" "\"virtio-blk-mmio\""
    # Keep template and cold-start benchmark configurations equivalent.
    local net_model="${NET_MODEL:-none}"
    if [ "$net_model" = "none" ]; then
        set_toml_key "$cfg" "runtime" "internetworking_model" "\"none\""
        set_toml_key "$cfg" "runtime" "disable_new_netns" "true"
    else
        set_toml_key "$cfg" "runtime" "internetworking_model" "\"$net_model\""
        set_toml_key "$cfg" "runtime" "disable_new_netns" "false"
    fi
    echo "$cfg"
}

show_factory_config() {
    grep -nE "dragonball.factory|enable_template|template_path" "$1" || true
}

# ---- subcommands ------------------------------------------------------------
cmd_create() {
    echo "=== [1/3] VM factory config ==="
    local cfg
    cfg="$(ensure_config create)" || exit 1
    show_factory_config "$cfg"
    point_config "$cfg"
    [ -x "$KATA_CTL" ] || die "kata-ctl not executable: $KATA_CTL"

    echo "=== [2/3] kata-ctl factory init ==="
    "$KATA_CTL" factory init

    echo "=== [3/3] verifying template files ==="
    if [ -s "$MEMORY_FILE" ] && [ -s "$STATE_FILE" ]; then
        ls -la "$TEMPLATE_PATH"
        echo "OK: template created."
    else
        die "template files missing/empty under $TEMPLATE_PATH -- check 'journalctl -t kata' / containerd logs"
    fi
}

# runp_timed <pod_json> : start a pod sandbox, print its id on stdout and the
# boot time on stderr. "Boot" here is the crictl runp duration -- the VM cold
# boot (run-cold) or template restore (run), plus agent connect + the guest
# CreateSandbox. This is the number to compare across run vs run-cold.
runp_timed() {
    local t0 t1 dur pod
    t0=$(date +%s.%N)
    pod="$(crictl runp --runtime "$RUNTIME_CRI" "$1")" || return 1
    t1=$(date +%s.%N)
    dur=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b - a}')
    echo ">>> sandbox boot (crictl runp) took ${dur}s <<<" >&2
    printf '%s' "$pod"
}

cmd_run() {
    echo "=== [1/3] VM factory restore config ==="
    local cfg ts pod_json ctr_json pod cid
    cfg="$(ensure_config run)" || exit 1
    show_factory_config "$cfg"
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
    pod="$(runp_timed "$pod_json")" || die "crictl runp failed"
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
    echo "=== cold start (VM factory disabled) ==="
    local cfg ts pod_json ctr_json pod cid
    cfg="$(ensure_config cold)" || exit 1
    show_factory_config "$cfg"
    point_config "$cfg"
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
    pod="$(runp_timed "$pod_json")" || die "crictl runp failed"
    cid="$(crictl create "$pod" "$ctr_json" "$pod_json")" || die "crictl create failed"
    crictl start "$cid" || die "crictl start failed"
    crictl pods --id "$pod"
    echo "container output: crictl logs $cid"
}

benchmark_trial() {
    local mode="$1" iteration="$2" cfg="$3"
    local ts pod_json pod t0 t1

    point_config "$cfg"
    mkdir -p "$RUNDIR"
    ts="$(date +%s%N)"
    pod_json="$RUNDIR/pod-benchmark-$mode-$ts.json"
    cat > "$pod_json" <<EOF
{
    "metadata": {
        "name": "kata-benchmark-$mode-$iteration",
        "namespace": "default",
        "uid": "kata-benchmark-$mode-$ts",
        "attempt": 0
    },
    "log_directory": "/tmp/kata-template-logs",
    "linux": {}
}
EOF

    t0="$(date +%s.%N)"
    pod="$(crictl runp --runtime "$RUNTIME_CRI" "$pod_json")" ||
        die "crictl runp failed for $mode iteration $iteration"
    t1="$(date +%s.%N)"
    BENCHMARK_ELAPSED="$(awk -v a="$t0" -v b="$t1" \
        'BEGIN { printf "%.6f", b - a }')"
    printf 'RESULT mode=%s iteration=%s elapsed=%ss pod=%s\n' \
        "$mode" "$iteration" "$BENCHMARK_ELAPSED" "$pod"

    crictl stopp "$pod" >/dev/null
    crictl rmp "$pod" >/dev/null
}

cmd_benchmark() {
    local template_cfg cold_cfg iteration
    local template_mean cold_mean speedup reduction
    local -a template_times=()
    local -a cold_times=()

    if [ ! -s "$MEMORY_FILE" ] || [ ! -s "$STATE_FILE" ]; then
        cmd_create
    fi
    template_cfg="$(ensure_config run)" || exit 1
    cold_cfg="$(ensure_config cold)" || exit 1

    echo "=== three VM template restores ==="
    for iteration in 1 2 3; do
        benchmark_trial template "$iteration" "$template_cfg"
        template_times+=("$BENCHMARK_ELAPSED")
    done

    echo "=== three cold VM starts ==="
    for iteration in 1 2 3; do
        benchmark_trial cold "$iteration" "$cold_cfg"
        cold_times+=("$BENCHMARK_ELAPSED")
    done

    template_mean="$(printf '%s\n' "${template_times[@]}" |
        awk '{ total += $1 } END { printf "%.6f", total / NR }')"
    cold_mean="$(printf '%s\n' "${cold_times[@]}" |
        awk '{ total += $1 } END { printf "%.6f", total / NR }')"
    speedup="$(awk -v cold="$cold_mean" -v template="$template_mean" \
        'BEGIN { printf "%.2f", cold / template }')"
    reduction="$(awk -v cold="$cold_mean" -v template="$template_mean" \
        'BEGIN { printf "%.1f", (cold - template) * 100 / cold }')"

    echo "=== averages ==="
    printf 'template restore: %ss\n' "$template_mean"
    printf 'cold start:       %ss\n' "$cold_mean"
    printf 'speedup:          %sx (%s%% less elapsed time)\n' \
        "$speedup" "$reduction"
    point_config "$template_cfg"
}

cmd_status() {
    echo "=== shim config ==="
    ls -la "$ACTIVE_LINK"
    echo "=== template files ($TEMPLATE_PATH) ==="
    ls -la "$TEMPLATE_PATH" 2>/dev/null || echo "(none)"
    echo "=== kata pods ==="
    crictl pods 2>/dev/null | head -10
}

cmd_clean() {
    echo "=== removing script-created pods ==="
    local pod cfg
    for pod in $(crictl pods -q --name kata-template-pod 2>/dev/null) \
               $(crictl pods -q --name kata-cold-pod 2>/dev/null) \
               $(crictl pods -q --name kata-benchmark 2>/dev/null); do
        crictl stopp "$pod" >/dev/null 2>&1
        crictl rmp "$pod" >/dev/null 2>&1 && echo "removed pod $pod"
    done

    echo "=== destroying VM factory ==="
    if [ -s "$MEMORY_FILE" ] && [ -s "$STATE_FILE" ]; then
        cfg="$(ensure_config run)" || exit 1
        point_config "$cfg"
        "$KATA_CTL" factory destroy ||
            echo "warn: kata-ctl factory destroy failed; cleaning path directly"
    fi
    if [ -e "$TEMPLATE_PATH" ]; then
        mountpoint -q "$TEMPLATE_PATH" && umount -l "$TEMPLATE_PATH"
        rm -rf "$TEMPLATE_PATH"
    fi

    echo "=== restoring original shim config ==="
    if [ -f "$ORIG_LINK_FILE" ] && [ -s "$ORIG_LINK_FILE" ]; then
        ln -sfn "$(cat "$ORIG_LINK_FILE")" "$ACTIVE_LINK"
        rm -f "$ORIG_LINK_FILE"
        echo "shim config -> $(readlink "$ACTIVE_LINK")"
    else
        echo "no saved original config link; leaving $ACTIVE_LINK as-is"
    fi
    rm -f "$CREATE_CONFIG" "$RUN_CONFIG" "$COLD_CONFIG"
    rm -rf "$RUNDIR"
}

# ---- dispatch ---------------------------------------------------------------
case "${1:-}" in
    create)    cmd_create ;;
    run)       cmd_run ;;
    run-cold)  cmd_run_cold ;;
    benchmark) cmd_benchmark ;;
    status)    cmd_status ;;
    clean)     cmd_clean ;;
    *)
        echo "Usage: bash $0 {create|run|run-cold|benchmark|status|clean}"
        echo "  create     create the VM template with kata-ctl factory init"
        echo "  run        start a pod through the enabled VM factory"
        echo "  run-cold   start a pod with the VM factory disabled"
        echo "  benchmark  compare three template restores and cold starts"
        echo "  status     show active config, template files and kata pods"
        echo "  clean      remove pods/template files, restore original config"
        exit 1 ;;
esac
