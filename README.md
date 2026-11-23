# Raspberry Pi 5 provisioning

Provisioning bundle for Raspberry Pi OS Bookworm / Debian-based Raspberry Pi OS.

## Included configuration

- APT packages: `packages.txt`
- Git identity: `config/git.conf`
- Netplan static IPv4: `config/99-static-ip.yaml`
- Provisioning paths/options: `config/provision.conf`
- Python source: `scripts/sysinfo.py` (placeholder; replace with your real script)
- Installer: `install.sh`

## Settings configured

- Interface: `eth0`
- Address: `10.20.30.200/24`
- Gateway: `10.20.30.1`
- DNS: `1.1.1.1`, `8.8.8.8`
- Netplan renderer: `NetworkManager`
- Git user: `breaking-bash`
- Git email: `navinsivasami@gmail.com`
- Python destination: `/usr/local/minitower/sysinfo.py`

## Before running

1. Replace `scripts/sysinfo.py` with your actual Python script. The included file is only a harmless example placeholder.
2. Confirm `10.20.30.200` is outside your DHCP pool or reserved for this Pi in your router.
3. Confirm the active network manager and interface name:
   ```bash
   ip -br link
   systemctl is-active NetworkManager
   ```
4. Netplan is not the default network configuration mechanism on every Raspberry Pi OS Bookworm image. This bundle installs `netplan.io` and `network-manager`, but it does not automatically disable or rewrite existing NetworkManager, dhcpcd, or cloud-init configuration. Review existing network configuration first to avoid competing managers or duplicate default routes.

## Run

```bash
chmod +x install.sh
sudo ./install.sh
```

The installer configures APT packages, Git, and copies the Python script. It writes and validates the Netplan file but deliberately does **not** apply it by default, to avoid unexpectedly losing SSH access.

After reviewing the configuration and ensuring you have local console/recovery access:

```bash
sudo netplan try
```

If the connection remains healthy and the confirmation succeeds:

```bash
sudo netplan apply
```

To opt into applying during provisioning, edit `config/provision.conf` and set:

```bash
APPLY_NETPLAN="yes"
```

Use that only when you have a reliable recovery path. If your existing setup uses Raspberry Pi OS's default networking stack rather than Netplan, decide on one network manager before switching.

## Logs

Each run writes a timestamped log under `logs/`.
