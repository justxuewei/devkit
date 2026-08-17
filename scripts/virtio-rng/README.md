# virtio-rng

End-to-end smoke test for the Dragonball virtio-rng device in a normal
(non-confidential) Kata VM.

The test temporarily points runtime-rs at a copy of the Dragonball
configuration with `entropy_source = "/dev/urandom"`, starts a pod sandbox,
and uses `kata-ctl exec` to verify directly in the guest that:

- a virtio device is bound to the Linux `virtio_rng` driver;
- `hw_random` selects a `virtio_rng` provider; and
- reading the guest hwrng character device returns 32 bytes.

Run it from this directory:

```bash
bash main.sh test
```

The script uses `sudo`, `crictl`, `kata-ctl`, `expect`, and the `kata` CRI
runtime handler. `expect` drives the guest's interactive debug console and
answers terminal setup queries before running the probe. Set `KATA_CTL=...` to
select a binary. Set `KEEP=1` to leave the pod and generated runtime
configuration in place for debugging, then remove them with:

```bash
bash main.sh clean
```

This test deliberately does not exercise TDX or validate
`VIRTIO_F_ACCESS_PLATFORM`; the production runtime does not expose the
host-backed RNG device to confidential guests.
