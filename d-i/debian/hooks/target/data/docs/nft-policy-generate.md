# nft-policy-generate helper guide

This guide is staged only when nftables policy generation is enabled for the
installed host.

## Purpose

`__INSTALLER_PATH_DIR_USR_LOCAL_SBIN__/nft-policy-generate` renders:

- `__INSTALLER_PATH_DIR_ETC__/nftables.conf`
- `__INSTALLER_PATH_DIR_ETC__/nftables.d/00-defines.nft`
- `__INSTALLER_PATH_DIR_ETC__/nftables.d/10-base.nft`
- `__INSTALLER_PATH_DIR_ETC__/nftables.d/20-filter.nft`
- `__INSTALLER_PATH_DIR_ETC__/nftables.d/30-nat.nft`
- `__INSTALLER_PATH_DIR_ETC__/nftables.d/90-local.nft`

from one profile YAML plus zero or more service overlay YAML files.

## Inputs

- default profile link: `__INSTALLER_PATH_DIR_ETC__/nftables/profiles/default.yml`
- profile catalog: `__INSTALLER_PATH_DIR_ETC__/nftables/profiles/*.yml`
- service overlays: `__INSTALLER_PATH_DIR_ETC__/nftables/services/*.yml`
- default generator env: `__INSTALLER_PATH_DIR_ETC__/nftables/policy.conf`

## Common commands

Regenerate the installed ruleset from the default profile:

```sh
env NFTABLES_LOG_LEVEL=info __INSTALLER_PATH_DIR_USR_LOCAL_SBIN__/nft-policy-generate \
  --profile __INSTALLER_PATH_DIR_ETC__/nftables/profiles/default.yml
```

Regenerate from an explicit profile plus overlays:

```sh
__INSTALLER_PATH_DIR_USR_LOCAL_SBIN__/nft-policy-generate \
  --profile __INSTALLER_PATH_DIR_ETC__/nftables/profiles/server.yml \
  --overlay __INSTALLER_PATH_DIR_ETC__/nftables/services/ssh-server.yml \
  --overlay __INSTALLER_PATH_DIR_ETC__/nftables/services/ssh-server.yml
```

Validate before reload:

```sh
nft -c -f __INSTALLER_PATH_DIR_ETC__/nftables.conf
systemctl reload nftables
```

## Notes

- The YAML files are declarative policy, not raw `nft` fragments.
- The generator writes deterministic managed fragments; edit the YAML inputs,
  not the generated `*.nft` files.
- `NFTABLES_LOG_LEVEL` controls generator diagnostics only. Packet logging is
  still controlled by the selected profile and overlay logging fields. The
  desktop profile enables bounded `nftables accept output` auditing plus final
  input/forward drop logging even when diagnostics are set to `none`.
