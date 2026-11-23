#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Copyright (c) 2014-2022 Richard Hull and contributors
# See LICENSE.rst for details.
# PYTHON_ARGCOMPLETE_OK

"""
Display basic system information.

Needs psutil and luma.core installed.
"""

import getpass
import os
import signal
import socket
import sys
import time
from datetime import datetime
from pathlib import Path

if os.name != "posix":
    sys.exit(f"{os.name} platform is not supported")

from demo_opts import get_device
from luma.core.render import canvas
from PIL import ImageFont

try:
    import psutil
except ImportError:
    print("The psutil library was not found. Install it with your package manager.")
    sys.exit(1)


def shutdown(signum, frame):
    device.clear()
    sys.exit(0)


signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)


def bytes2human(n):
    """Convert a byte count to a short human-readable value."""
    symbols = ("K", "M", "G", "T", "P", "E", "Z", "Y")
    prefix = {}

    for i, symbol in enumerate(symbols):
        prefix[symbol] = 1 << ((i + 1) * 10)

    for symbol in reversed(symbols):
        if n >= prefix[symbol]:
            value = int(float(n) / prefix[symbol])
            return f"{value}{symbol}"

    return f"{n}B"


def cpu_usage():
    """Return CPU load and system uptime."""
    uptime = datetime.now() - datetime.fromtimestamp(psutil.boot_time())
    days = uptime.days
    hours, remainder = divmod(uptime.seconds, 3600)
    minutes, _ = divmod(remainder, 60)

    cpu_percent = psutil.cpu_percent(interval=1)
    return f"CPU: {cpu_percent:.0f}% Up: {days}d{hours}h{minutes}m"


def mem_usage():
    """Return used and total memory."""
    usage = psutil.virtual_memory()
    return "RAM: %s/%s (%.0f%%)" % (
        bytes2human(usage.used),
        bytes2human(usage.total),
        usage.percent,
    )


def disk_usage(path):
    """Return used and total disk space."""
    usage = psutil.disk_usage(path)
    return "SD: %s/%s (%.0f%%)" % (
        bytes2human(usage.used),
        bytes2human(usage.total),
        usage.percent,
    )


def get_lan_info():
    """Return the active Ethernet or Wi-Fi interface and its IPv4 address."""
    addresses = psutil.net_if_addrs()
    interface_stats = psutil.net_if_stats()

    # Prefer Ethernet; fall back to Wi-Fi.
    names = sorted(
        (
            name
            for name in addresses
            if name.startswith(("eth", "en", "wlan", "wl"))
            and not name.startswith(("tailscale", "docker"))
        ),
        key=lambda name: (
            name.startswith(("wlan", "wl")),
            name,
        ),
    )

    for name in names:
        stats = interface_stats.get(name)
        if not stats or not stats.isup:
            continue

        for address in addresses[name]:
            if (
                address.family == socket.AF_INET
                and not address.address.startswith("127.")
            ):
                return name, address.address

    return None, None


def stats(device):
    font_path = str(
        Path(__file__).resolve().parent.joinpath(
            "fonts", "DejaVuSansMono.ttf"
        )
    )
    font = ImageFont.truetype(font_path, 8)
    ascent, descent = font.getmetrics()
    line_height = ascent + descent

    interface, ip_address = get_lan_info()
    lan_text = f"LAN: {interface}" if interface else "LAN: disconnected"
    ip_text = f"IP: {ip_address}" if ip_address else "IP: unavailable"

    lines = [
        cpu_usage(),
        mem_usage(),
        disk_usage("/"),
        lan_text,
        ip_text,
        f"User: {getpass.getuser()}",
    ]

    with canvas(device) as draw:
        draw.rectangle(device.bounding_box, outline="white", fill=None)

        for row, line in enumerate(lines):
            y = row * line_height
            if y + line_height > device.height:
                break
            draw.text((2, y), line, font=font, fill="white")


def main():
    while True:
        stats(device)
        time.sleep(5)


if __name__ == "__main__":
    device = None
    try:
        device = get_device()
        main()
    except KeyboardInterrupt:
        pass
    finally:
        if device is not None:
            device.clear()
