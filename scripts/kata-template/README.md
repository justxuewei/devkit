# kata-template

Dev helper for testing dragonball VM template save/restore in upstream kata
(runtime-rs), modeled on `~/developer/devkit-ant/scripts/rund-template`.

## Workflow

```bash
bash main.sh create    # create a template: nerdctl boots a throwaway kata pod,
                       # the sandbox VM is dumped at boot (memory + state files)
bash main.sh run       # start a pod from the template via crictl
bash main.sh run-cold  # baseline: same pod, plain dragonball config
bash main.sh status    # active config, template files, pods
bash main.sh clean     # remove pods + template, restore original config symlink
```

The shim is NOT installed by this script: `/usr/local/bin/containerd-shim-kata-v2`
is a symlink into the repo's musl debug build
(`src/runtime-rs/target/x86_64-unknown-linux-musl/debug/`) — build the shim with
the dragonball snapshot changes yourself and the symlink picks it up.

## How it maps to the implementation

- The shim loads `/etc/kata-containers/runtime-rs/configuration.toml` (a
  symlink). The script forks `configuration.db.toml` into
  `configuration.db.template-{create,run}.toml`, sets the flattened
  `[hypervisor.dragonball]` keys `boot_to_be_template` / `boot_from_template` /
  `memory_path` / `device_state_path`, and repoints the symlink per mode.
- `create`: with `boot_to_be_template = true`, the sandbox VM is snapshotted
  right after the guest sandbox is created (`VirtSandbox::start` →
  `hypervisor.save_vm()` → `VmmAction::SaveMicrovm` → `Vm::save_microvm`),
  with branch semantics (VM paused for capture, then resumed) — so the
  throwaway container finishes normally and is removed.
- `run`: with `boot_from_template = true`, `DragonballInner::start_vmm_instance`
  takes the `StartMicroVmFromSnapshot` path: guest RAM is reloaded from
  `memory_path`, vCPU/device state from `device_state_path`, virtio activation
  is replayed, and the vCPUs resume where the template left off.

## Caveats (v1 restore semantics)

- The run pod must be configured identically to the template pod (same VM
  size, same device set — image, no network on both sides): restore validates
  layout/feature mismatches and refuses loudly.
- Live vsock connections / virtiofs backend state are not captured; the
  template is taken at a clean quiesce point (sandbox created, no workload).
- Regenerate the template after rebuilding the shim (`sync`) — snapshots are
  same-version by policy (`format_epoch` refuses stale ones only across
  incompatible format changes).

## Debugging

- Shim/hypervisor logs: `journalctl -t kata -f` or containerd logs.
- Snapshot state file is JSON: `python3 -m json.tool /run/vc/vm/template/state | less`.
