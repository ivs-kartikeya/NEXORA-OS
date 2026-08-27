#!/usr/bin/env bash
set -euo pipefail

sudo apt update
sudo apt install -y \
  git build-essential cmake ninja-build pkg-config ca-certificates curl python3-venv python3-pip \
  libcurl4-openssl-dev \
  qt6-base-dev qt6-declarative-dev qt6-wayland-dev libkf6config-bin \
  qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts \
  qml6-module-qtquick-window qml6-module-qtqml-workerscript qml6-module-qtquick-dialogs \
  qml6-module-org-kde-layershell layer-shell-qt liblayershellqtinterface-dev \
  inotify-tools python3 sqlite3 dbus-user-session dbus-x11 kwin-wayland xwayland \
  polkitd pkexec polkit-kde-agent-1 \
  xdg-desktop-portal xdg-desktop-portal-kde \
  open-vm-tools open-vm-tools-desktop mesa-utils \
  fonts-noto-core fonts-dejavu-core pipewire pipewire-pulse pipewire-bin wireplumber pulseaudio-utils alsa-utils espeak-ng ffmpeg \
  flatpak brightnessctl network-manager rfkill bluez power-profiles-daemon wl-clipboard \
  live-build debootstrap squashfs-tools xorriso rsync

echo "Nexora OS V1 bootstrap complete."

if command -v flatpak >/dev/null 2>&1; then
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
fi
