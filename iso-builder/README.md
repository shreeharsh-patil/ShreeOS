# ISO Builder

Build a hybrid BIOS/UEFI ISO with:

```bash
bash iso-builder/scripts/build-iso.sh
```

Inputs are `build/build-kernel/arch/x86/boot/bzImage` and the canonical
`build/initramfs.cpio.gz`. The generated ISO is written to `out/`.
