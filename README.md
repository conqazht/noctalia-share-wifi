# Share WiFi

Share a Wi-Fi hotspot from your Linux laptop without dropping your current Wi-Fi connection, featuring auto-detected frequency band & channel, and hardware-enforced client limits.

## Plugin

| Field | Value |
| --- | --- |
| ID | `conqazht/share-wifi` |
| Entries | Bar widget: `widget`; panel: `panel`; shortcut: `shortcut` |

## Requirements

Install `create_ap`, `nmcli`, `iw`, and `pkexec` on `PATH`.

- Arch Linux:
  ```sh
  yay -S create_ap
  ```
- Debian / Ubuntu:
  ```sh
  sudo apt install create_ap network-manager iw policykit-1
  ```

### Optional: Passwordless Hotspot

To start/stop hotspots from the bar without entering your password each time, add a sudoers rule:

```sh
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/create_ap" | sudo tee /etc/sudoers.d/noctalia-share-wifi
```

## Usage

### Bar Widget

Add `widget` to your bar configuration in Noctalia settings.
- **Click**: Open or close the hotspot configuration panel.
- **Right-Click**: Turn off the hotspot immediately if active.
- **Badge**: Displays the active connection count and maximum limit (e.g. `0/2` or `1/2`).

### Panel

Open the configuration panel using IPC:

```sh
noctalia msg panel-toggle conqazht/share-wifi:panel
```

Inside the panel:
- **SSID & Password**: Configure your hotspot network name and WPA2 passphrase (minimum 8 characters).
- **Frequency band**: Choose `Auto`, `5Ghz`, or `2.4Ghz`.
- **Channel**: Specify an exact channel number or leave blank for Auto.
- **Max clients (1 - 8)**: Set a connection limit (default `2`, maximum `8`) to prevent laptop Wi-Fi hardware saturation.
- **Auto-detection**: Automatically detects your current active Wi-Fi channel and frequency band, with a manual refresh button (`refresh`).

### Shortcut

Add `shortcut` to your Control Center in Noctalia Settings for quick toggling.

## Notes

- **Simultaneous Wi-Fi & Hotspot**: Uses Linux kernel virtual interface `ap0` on top of your physical Wi-Fi interface (`wlan0`), allowing your laptop to remain connected to the internet while simultaneously sharing it.
- **Client Limit**: Enforced at the 802.11 MAC management frame level via `hostapd` (`max_num_sta`).
