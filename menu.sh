#!/bin/bash
# FIX NHANH - ten cu cua menu, giu lai de lenh tat proxmox-menu, timer, huong dan cu van chay.
# Menu that: proxmox-ceph-monitor.sh (cung thu muc).
exec bash "$(cd "$(dirname "$0")" && pwd)/proxmox-ceph-monitor.sh" "$@"
