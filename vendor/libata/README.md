# libata native bundles

Prebuilt native libraries for linking Yozgat against `ata-validator-crystal`.

| Path | Platform | Contents |
|------|----------|----------|
| `linux-x64/` | Linux x86_64 (VPS / CI release) | `libata.so` + transitive `.so` dependencies |
| `win-x64/` | Windows local dev | `ata.dll`, `ata.lib` |

## Updating the Linux bundle

When `ata-core/ata-validator` changes, rebuild on Linux and replace `linux-x64/`:

```bash
bash scripts/build-libata-bundle.sh
git add vendor/libata/linux-x64 MANIFEST
```

Or extract `.so*` files from a known-good release tarball into `linux-x64/`.

`MANIFEST` records the `ata-validator` git SHA the bundle was built from.
