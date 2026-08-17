#!/bin/bash
export LANG=""

# End-to-end smoke test for Dragonball's virtio-rng device.

set -euo pipefail

KATA_ETC="/etc/kata-containers"
RRS_DIR="$KATA_ETC/runtime-rs"
BASE_CONFIG="$RRS_DIR/configuration.db.toml"
TEST_CONFIG="$RRS_DIR/configuration.db.virtio-rng.toml"
ACTIVE_LINK="$RRS_DIR/configuration.toml"
ORIG_LINK_FILE="$RRS_DIR/.virtio-rng.orig-link"

RUNTIME_CRI="${RUNTIME_CRI:-kata}"
KEEP="${KEEP:-0}"

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNDIR="$WORKDIR/run"
POD_FILE="$RUNDIR/pod-id"
KATA_REPO="$(cd "$WORKDIR/../../.." && pwd)/kata-containers"
KATA_CTL="${KATA_CTL:-$(command -v kata-ctl 2>/dev/null || true)}"
KATA_CTL="${KATA_CTL:-$KATA_REPO/target/x86_64-unknown-linux-musl/debug/kata-ctl}"

die() {
    echo "Error: $*" >&2
    exit 1
}

# Everything below needs root for the containerd socket and /etc updates.
[ "$(id -u)" -eq 0 ] || exec sudo -E bash "$0" "$@"

# set_toml_key <file> <section> <key> <value>
set_toml_key() {
    local file="$1" section="[$2]" key="$3" value="$4" tmp
    tmp="$(mktemp)"
    awk -v section="$section" -v key="$key" -v value="$value" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        BEGIN { insec=0; done=0 }
        {
            t=trim($0)
            if (t ~ /^\[/) {
                if (insec && !done) { print key " = " value; done=1 }
                insec=(t == section)
                print
                next
            }
            if (insec && !done && t ~ ("^#?[ \t]*" key "[ \t]*=")) {
                print key " = " value
                done=1
                next
            }
            print
        }
        END {
            if (insec && !done) { print key " = " value; done=1 }
            if (!done) { print ""; print section; print key " = " value }
        }
    ' "$file" > "$tmp"
    /usr/bin/cp -f "$tmp" "$file"
    rm -f "$tmp"
}

save_original_config() {
    if [ ! -f "$ORIG_LINK_FILE" ]; then
        readlink "$ACTIVE_LINK" > "$ORIG_LINK_FILE" 2>/dev/null || : > "$ORIG_LINK_FILE"
    fi
}

configure_runtime() {
    [ -f "$BASE_CONFIG" ] || die "Dragonball config not found: $BASE_CONFIG"
    save_original_config
    /usr/bin/cp -f "$BASE_CONFIG" "$TEST_CONFIG"
    set_toml_key "$TEST_CONFIG" "hypervisor.dragonball" \
        "entropy_source" '"/dev/urandom"'
    set_toml_key "$TEST_CONFIG" "hypervisor.dragonball.factory" \
        "enable_template" "false"
    set_toml_key "$TEST_CONFIG" "runtime" \
        "internetworking_model" '"none"'
    set_toml_key "$TEST_CONFIG" "runtime" \
        "disable_new_netns" "true"
    set_toml_key "$TEST_CONFIG" "agent.kata" \
        "debug_console_enabled" "true"
    ln -sfn "$TEST_CONFIG" "$ACTIVE_LINK"
    echo "shim config -> $(readlink "$ACTIVE_LINK")"
}

remove_workload() {
    local pod=""
    [ -s "$POD_FILE" ] && pod="$(cat "$POD_FILE")"

    if [ -n "$pod" ]; then
        crictl stopp "$pod" >/dev/null 2>&1 || true
        crictl rmp "$pod" >/dev/null 2>&1 || true
    fi
    rm -f "$POD_FILE" "$RUNDIR"/pod-*.json
}

restore_runtime() {
    if [ -f "$ORIG_LINK_FILE" ]; then
        if [ -s "$ORIG_LINK_FILE" ]; then
            ln -sfn "$(cat "$ORIG_LINK_FILE")" "$ACTIVE_LINK"
            echo "shim config restored -> $(readlink "$ACTIVE_LINK")"
        fi
        rm -f "$ORIG_LINK_FILE"
    fi
    rm -f "$TEST_CONFIG"
}

cleanup() {
    local rc=$?
    trap - EXIT
    if [ "$KEEP" = "1" ]; then
        echo "KEEP=1: leaving the workload and test configuration in place"
    else
        remove_workload
        restore_runtime
        rmdir "$RUNDIR" 2>/dev/null || true
    fi
    exit "$rc"
}

create_workload() {
    local ts pod_json pod
    mkdir -p "$RUNDIR" /tmp/virtio-rng-logs
    ts="$(date +%s%N)"
    pod_json="$RUNDIR/pod-$ts.json"

    cat > "$pod_json" <<EOF
{
    "metadata": {
        "name": "kata-virtio-rng-$ts",
        "namespace": "default",
        "uid": "kata-virtio-rng-$ts",
        "attempt": 0
    },
    "log_directory": "/tmp/virtio-rng-logs",
    "linux": {}
}
EOF

    pod="$(crictl runp --runtime "$RUNTIME_CRI" "$pod_json")" || \
        die "crictl runp failed"
    echo "$pod" > "$POD_FILE"
    echo "pod: $pod"
}

probe_guest_rng() {
    local pod probe
    pod="$(cat "$POD_FILE")"
    [ -x "$KATA_CTL" ] || die "kata-ctl not executable: $KATA_CTL"
    read -r -d '' probe <<'EOF' || true
set -eu

driver=/sys/bus/virtio/drivers/virtio_rng
test -d "$driver" || {
    echo "FAIL: Linux virtio_rng driver is absent" >&2
    exit 1
}

bound=""
for device in "$driver"/virtio*; do
    if [ -e "$device" ]; then
        bound="$device"
        break
    fi
done
test -n "$bound" || {
    echo "FAIL: no virtio device is bound to virtio_rng" >&2
    exit 1
}

hwrng=/sys/class/misc/hw_random
test -r "$hwrng/rng_available" || {
    echo "FAIL: hw_random sysfs interface is absent" >&2
    exit 1
}
available="$(cat "$hwrng/rng_available")"
current="$(cat "$hwrng/rng_current")"
case " $available " in
    *" virtio_rng "*|*" virtio_rng."*) ;;
    *) echo "FAIL: virtio_rng not available: $available" >&2; exit 1 ;;
esac
case "$current" in
    virtio_rng|virtio_rng.*) ;;
    *) echo "FAIL: virtio_rng is not current: $current" >&2; exit 1 ;;
esac

output=/tmp/virtio-rng.bin
test -c /dev/hwrng || {
    echo "FAIL: guest devtmpfs has no /dev/hwrng" >&2
    exit 1
}
rm -f "$output"
timeout 10 dd if=/dev/hwrng of="$output" bs=32 count=1 2>/dev/null
bytes="$(wc -c < "$output" | tr -d ' ')"
rm -f "$output"
test "$bytes" -eq 32 || {
    echo "FAIL: expected 32 bytes from hwrng, got $bytes" >&2
    exit 1
}

echo "driver_device=$(basename "$bound")"
echo "rng_available=$available"
echo "rng_current=$current"
echo "bytes_read=$bytes"
echo "PASS: Dragonball virtio-rng is usable in the guest"
EOF

    command -v expect >/dev/null || die "expect is required to drive the guest console"
    local probe_b64
    probe_b64="$(printf '%s' "$probe" | base64 -w0)"

    # This guest's interactive shell asks the terminal for its cursor position
    # during startup. Answer that query, disable input echo, then send a
    # base64-encoded probe so shell quoting cannot change its contents.
    KATA_CTL_PATH="$KATA_CTL" SANDBOX_ID="$pod" PROBE_B64="$probe_b64" expect <<'EOF'
set timeout 45
log_user 0

spawn $env(KATA_CTL_PATH) exec $env(SANDBOX_ID)
set ready 0
while {!$ready} {
    expect {
        -exact "\033\[6n" {
            send -- "\033\[1;1R"
            exp_continue
        }
        -exact "#" {
            set ready 1
        }
        timeout {
            puts stderr "FAIL: timed out waiting for the guest console prompt"
            exit 124
        }
        eof {
            puts stderr "FAIL: guest console closed before its prompt"
            exit 1
        }
    }
}

send -- "stty -echo\r"
expect {
    -exact "#" {}
    timeout {
        puts stderr "FAIL: timed out preparing the guest console"
        exit 124
    }
    eof {
        puts stderr "FAIL: guest console closed during setup"
        exit 1
    }
}

set command [format {echo __KATA_RNG_BEGIN__; printf '%%s' '%s' | base64 -d | sh; rc=$?; echo __KATA_RNG_RC=$rc; echo __KATA_RNG_END__} $env(PROBE_B64)]
log_user 1
send -- "$command\r"

set rc -1
set finished 0
while {!$finished} {
    expect {
        -re {__KATA_RNG_RC=([0-9]+)} {
            set rc $expect_out(1,string)
            exp_continue
        }
        -exact "__KATA_RNG_END__" {
            set finished 1
        }
        timeout {
            puts stderr "FAIL: timed out running the guest virtio-rng probe"
            exit 124
        }
        eof {
            puts stderr "FAIL: guest console closed during the virtio-rng probe"
            exit 1
        }
    }
}

log_user 0
send -- "exit\r"
expect eof
if {$rc < 0} {
    puts stderr "FAIL: guest probe did not report an exit status"
    exit 1
}
exit $rc
EOF
}

cmd_test() {
    trap cleanup EXIT INT TERM
    remove_workload
    configure_runtime
    create_workload
    probe_guest_rng
}

cmd_clean() {
    remove_workload
    restore_runtime
    rmdir "$RUNDIR" 2>/dev/null || true
}

case "${1:-test}" in
    test)  cmd_test ;;
    clean) cmd_clean ;;
    *)
        echo "Usage: bash $0 {test|clean}"
        exit 1
        ;;
esac
