# Security model

This plugin installs code that runs as root. This page explains what that code
does, what limits it, and what it protects you from.

## Two parts, two privilege levels

| Part | Runs as | Can access |
|---|---|---|
| `BarWidget.qml` | Your user, inside `omarchy-shell` | Reads `/run/peripheral-battery/status.json`. That is all it does. |
| `peripheral-battery` (service) | root, sandboxed, no capabilities | `/dev/hidraw*` read/write, `/sys` read-only, writes `/run/peripheral-battery/` |

The widget never talks to the devices, starts no process and needs no
permission.

## Why not a udev rule instead?

`/dev/hidraw*` nodes belong to `root:root` with mode `0600`. Solaar and
HeadsetControl make them usable with udev rules that add the `uaccess` tag,
which gives the logged-in user read/write access:

| Rule | Package | Grants your user |
|---|---|---|
| `42-logitech-unify-permissions.rules` | solaar | Every Logitech hidraw node (`046d:*`) and `/dev/uinput` |
| `70-headsets.rules` | headsetcontrol | hidraw nodes of about 140 headset models |

With that access, any program running under your account can:

- read and change device settings (DPI, lighting, onboard profiles, firmware
  update mode),
- read the raw reports passing through a Logitech receiver. On a keyboard
  receiver, those include **keystrokes**.
- through `/dev/uinput`, create a virtual keyboard or mouse and **inject
  input**.

hidraw has no read-only mode and cannot filter report types, so a udev rule
cannot grant "battery only". The only way to give your session battery levels
and nothing more is to keep device access with root and publish only the
result. This plugin does exactly that.

## What the service sends to the devices

Only read requests. It never writes a setting.

**Logitech HID++ 2.0** (report `0x10`/`0x11`, software id `0x0B`):

| Feature | Function | Purpose |
|---|---|---|
| `0x0000` Root | 1 `ping` | Is something paired in this slot, and which protocol version? |
| `0x0000` Root | 0 `getFeature` | Look up the index of the features below |
| `0x0005` Device name | 0 `getCount`, 1 `getName`, 2 `getType` | Name and kind (mouse, keyboard…) shown in the bar |
| `0x1004` Unified battery | 1 `getStatus` | Charge and charging state |
| `0x1000` Battery status | 0 `getLevel` | Same, older devices |
| `0x1001` Battery voltage | 0 `getVoltage` | Same, from the voltage (converted to %) |

Slots 1–6 of each receiver are pinged. Devices connected by cable or Bluetooth
use the direct address `0xFF`.

**SteelSeries Arctis** (vendor `1038`): one status request, on the one
interface that carries it, taken from HeadsetControl. No other message is sent.

| Models | Interface | Request |
|---|---|---|
| Arctis 7 (2017, 2019) | 5 | `06 18` |
| Arctis 1 Wireless, 7P, 7X | 3 | `06 12` |
| Arctis 9 | 0 | `00 20` |
| Arctis 7+, 7P+, 7X+, Nova 3P/3X Wireless, Nova 5/5X, Nova 7/7X/7P | 3 | `00 b0` |
| Arctis Nova Pro Wireless | 4 | `06 b0`, padded to 31 bytes |

The replies hold the charge, a charging flag and a "headset off" flag. See
`ARCTIS_MODELS` in `service/peripheral-battery` for the byte layout of each.

**Kernel batteries** (`/sys/class/power_supply`, entries with
`SCOPE=Device`): read-only attributes. The service sends nothing to these
devices; the kernel driver may query the device itself when the attribute is
read, as it does for UPower.

## What happens to the data it reads

A receiver's hidraw node carries every report from the paired devices,
including key presses and mouse movement, while it is open. The service keeps
each node open for a fraction of a second. It checks each incoming report
against the reply it is waiting for (report id, device index, feature index,
function, software id) and drops everything else on the spot. It never decodes,
stores or logs input reports. See `read_matching()` in `service/peripheral-battery`.

The output file contains only, for each device: a name, a kind, a percentage,
a charging state, an online flag and timestamps.

## Sandbox

From `service/peripheral-battery.service`:

| Setting | Effect |
|---|---|
| `Type=oneshot` + timer | Runs for under a second every 30 s (about 60 ms of CPU), never resident |
| `CapabilityBoundingSet=` (empty), `NoNewPrivileges=yes` | root without any capability: cannot override file permissions, load modules, mount, change network or clock… |
| `DevicePolicy=closed`, `DeviceAllow=char-hidraw rw` | No device except hidraw (and `/dev/null` and similar pseudo devices) |
| `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes` | Entire filesystem read-only, `/home` invisible. Only writable path: `/run/peripheral-battery/` |
| `PrivateNetwork=yes`, `IPAddressDeny=any`, `RestrictAddressFamilies=AF_UNIX` | No network |
| `ProtectKernel*`, `ProtectControlGroups`, `ProtectClock`, `ProtectHostname`, `ProtectProc=invisible` | Kernel and system state untouchable, other processes invisible |
| `SystemCallFilter=@system-service ~@privileged @resources`, `MemoryDenyWriteExecute`, `RestrictNamespaces`, `RestrictSUIDSGID`, `LockPersonality`… | Reduced kernel attack surface |

Check the result on your machine with:

```bash
systemd-analyze security peripheral-battery.service
```

## Where the root code lives

`install.sh` copies the script to `/usr/local/lib/peripheral-battery/`, owned
by root. The service never executes the copy in
`~/.config/omarchy/plugins/`: your user can write there, and so can any
program running as you. A root service running it would hand root to that
program.

As a consequence, `omarchy plugin update` does not change what runs as root.
New service code only takes effect when you re-run `sudo service/install.sh`,
so you can review the diff (`git -C ~/.config/omarchy/plugins/gexavi.peripheral-battery log -p`)
first.

## What this does not protect against

- **A malicious version of this plugin.** If you install a compromised
  `install.sh` with sudo, it can do anything. Read it before running it, and
  again before re-running it after an update.
- **Malware already running as your user.** It can still read your files,
  browser data and so on. This plugin only avoids adding raw device access to
  that list.
- **Other udev rules.** If Solaar, HeadsetControl or anything else installed
  `uaccess` rules for these devices, your user keeps that access until you
  remove them. Check with `getfacl /dev/hidraw*`.
