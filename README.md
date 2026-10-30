# Peripheral Battery

An Omarchy bar widget that shows the battery level of your wireless mouse,
keyboard and headset, without Solaar or HeadsetControl.

<p align="center">
  <img src="preview.png" alt="Bar showing mouse 68%, keyboard 82% and headset 41%" width="420">
</p>

- **Hover** for the full device names, charging state, and when a sleeping
  device was last read.
- A device at **20 %** or below switches to the theme's alert color.
- ⚡ means the device is charging.
- Devices that are asleep or switched off are **dimmed** and keep their last
  reading for up to 12 hours instead of disappearing from the bar.

## How it works

```
 /dev/hidraw*  ──►  peripheral-battery.service  ──►  /run/peripheral-battery/status.json  ──►  bar widget
  (root only)       (root, sandboxed, every 2 min)        (world-readable, percentages only)    (reads the file)
```

The plugin comes in two parts:

1. **A system service** (`service/`). A short Python script, standard library
   only, that a systemd timer runs every 2 minutes. It asks each device for its
   battery level, writes the result to `/run/peripheral-battery/status.json`,
   and exits. Nothing stays resident: a run takes about 0.4 s, most of it
   waiting for the radio replies.
2. **The bar widget** (`BarWidget.qml`). It reads that JSON file and nothing
   else. It starts no process and needs no permission.

### Why a root service?

Reading the battery means talking to the devices through `/dev/hidraw*`,
which only root can open. Solaar and HeadsetControl solve this with udev
rules that give **your user account** raw read/write access to the devices
(and, for Solaar, to `/dev/uinput`). That access is broader than battery
reading. Any program running as you could also see the raw reports going
through a Logitech receiver, including keystrokes, or inject input.

This plugin keeps that access with root, inside a heavily sandboxed service
that has no capabilities, no network, a read-only filesystem and only hidraw
devices. All your desktop session gets is a few percentages in a JSON file.

[docs/security.md](docs/security.md) has the full details: every message sent
to the devices, the sandbox settings, and what is and is not protected.

## Supported hardware

| Device | Connection | Status |
|---|---|---|
| Logitech G502 Lightspeed | Lightspeed receiver `046d:c539` | Tested |
| Logitech G915 TKL | Lightspeed receiver `046d:c545` | Tested |
| SteelSeries Arctis 7 (2019) | USB dongle `1038:12ad` | Tested |
| Other Logitech HID++ 2.0 devices with battery feature `0x1000`, `0x1001` or `0x1004` (Unifying, Bolt, Lightspeed, cable or Bluetooth) | | Should work, untested |
| Legacy HID++ 1.0 Logitech devices, other headsets | | Not supported |

If your device works, or does not, please open an issue with its name and
the output of `cat /run/peripheral-battery/status.json`.

## Install

Plugins run as unsandboxed code inside `omarchy-shell`, and this one also
installs a root service. Read the code before installing: the service script
and the install script are short.

**1. Add the plugin**

```bash
omarchy plugin add https://github.com/gexavi/omarchy-peripheral-battery --enable
```

**2. Install the service**

`omarchy plugin add` never runs sudo or install scripts, so this step is
yours to run:

```bash
sudo ~/.config/omarchy/plugins/gexavi.peripheral-battery/service/install.sh
```

The script:

- copies the reader to `/usr/local/lib/peripheral-battery/`, root-owned. The
  root service never runs code from your home directory, which your user
  could modify.
- installs `peripheral-battery.service` and `peripheral-battery.timer` into
  `/etc/systemd/system/`,
- enables the timer and does a first reading.

Python 3 is required, and Omarchy ships with it.

**3. Restart the shell**

```bash
omarchy restart shell
```

Until the service is installed, the widget shows 󰂑. Hover over it for the
install command.

## Update

```bash
omarchy plugin update gexavi.peripheral-battery
sudo ~/.config/omarchy/plugins/gexavi.peripheral-battery/service/install.sh
omarchy restart shell
```

`omarchy plugin update` only updates the files in your home directory. The
root service keeps running the copy in `/usr/local/lib` until you re-run
`install.sh`, so you can review the diff first. If the service and the widget
versions differ, the tooltip warns you.

The shell restart is needed because Quickshell keeps the previous widget code
in memory.

## Uninstall

```bash
sudo ~/.config/omarchy/plugins/gexavi.peripheral-battery/service/uninstall.sh
omarchy plugin remove gexavi.peripheral-battery
```

## Coming from Solaar or HeadsetControl

The plugin works whether or not they are installed. If you installed them
only to read battery levels, you can remove them:

```bash
sudo pacman -Rs solaar headsetcontrol
```

This also removes their udev rules (`42-logitech-unify-permissions.rules`,
`70-headsets.rules`), and with them your user's raw access to the devices.
Keep them if you use them for something else, such as DPI, lighting or
sidetone.

## Troubleshooting

```bash
systemctl status peripheral-battery.timer       # is the timer active?
journalctl -u peripheral-battery.service        # errors from the last runs
sudo systemctl start peripheral-battery.service # read the devices now
cat /run/peripheral-battery/status.json         # what the widget sees
```

| Widget shows | Meaning |
|---|---|
| 󰂑, dimmed | `status.json` missing: the service is not installed or has not run yet |
| Readings dimmed | Not updated for 10 minutes: the timer is stopped |
| A device is missing | It was never seen awake, or it is not supported |

## Credits

The HID++ 2.0 battery features and the Li-ion voltage-to-percent curve
come from [Solaar](https://github.com/pwr-Solaar/Solaar). The Arctis 7 status
request comes from [HeadsetControl](https://github.com/Sapd/HeadsetControl).
This plugin reimplements the few requests it needs and contains no code from
either project.

## License

MIT
