# kata-template

Dev helper for testing dragonball VM template save/restore in upstream kata
(runtime-rs), modeled on `~/developer/devkit-ant/scripts/rund-template`.

## Workflow

```bash
bash main.sh create     # create a template with kata-ctl factory init
bash main.sh run        # start a pod through the enabled VM factory
bash main.sh run-cold   # start the equivalent pod with the factory disabled
bash main.sh benchmark  # average three template restores and three cold starts
bash main.sh status     # active config, template files, pods
bash main.sh clean      # factory destroy, remove pods, restore original config
```

The shim is NOT installed by this script: `/usr/local/bin/containerd-shim-kata-v2`
is a symlink into the repo's musl debug build
(`src/runtime-rs/target/x86_64-unknown-linux-musl/debug/`) — build the shim with
the dragonball snapshot changes yourself and the symlink picks it up.

`kata-ctl` must be built with `--features dragonball`. Set `KATA_CTL` to select
the binary; otherwise the script uses `kata-ctl` from `PATH`, then falls back to
the sibling kata-containers repository's musl debug build.

## How it maps to the implementation

- The shim loads `/etc/kata-containers/runtime-rs/configuration.toml` (a
  symlink). The script forks `configuration.db.toml` into
  `configuration.db.template-{create,run,cold}.toml` and repoints the symlink
  per mode.
- `create`: enables `[hypervisor.dragonball.factory]` and invokes
  `kata-ctl factory init`. kata-ctl boots the source VM, waits for kata-agent,
  disconnects it, saves the snapshot, and tears down the source sandbox.
- `run`: keeps the factory enabled. Runtime-rs derives the internal
  `boot_from_template`, memory, and device-state settings and restores the VM.
- `run-cold`: uses the same MMIO and network configuration with
  `factory.enable_template = false`.
- `clean`: invokes `kata-ctl factory destroy` before restoring the original
  runtime configuration symlink.

## Caveats (v1 restore semantics)

- The run pod must be configured identically to the template pod (same VM
  size, same device set — image, no network on both sides): restore validates
  layout/feature mismatches and refuses loudly.
- The factory disconnects kata-agent before saving so the restored runtime can
  establish a fresh connection.
- Regenerate the template after rebuilding the shim (`sync`) — snapshots are
  same-version by policy (`format_epoch` refuses stale ones only across
  incompatible format changes).

## Debugging

- Shim/hypervisor logs: `journalctl -t kata -f` or containerd logs.
- Snapshot state file is JSON: `python3 -m json.tool /run/vc/vm/template/state | less`.
