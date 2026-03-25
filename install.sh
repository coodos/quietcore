#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo bash install.sh"
    exit 1
fi

check_deps() {
    local missing=()
    command -v tlp &>/dev/null || missing+=("tlp")
    [[ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]] || missing+=("intel_pstate (CPU not supported)")
    [[ -f /sys/firmware/acpi/platform_profile ]] || missing+=("ACPI platform profiles (kernel/firmware not supported)")
    if (( ${#missing[@]} )); then
        echo "Missing requirements:"
        for m in "${missing[@]}"; do echo "  - $m"; done
        exit 1
    fi
}

install_files() {
    echo "Installing cpu-profile-switch..."
    install -m 755 "$SCRIPT_DIR/cpu-profile-switch" /usr/local/bin/cpu-profile-switch

    echo "Installing quietcore CLI..."
    install -m 755 "$SCRIPT_DIR/quietcore" /usr/local/bin/quietcore

    echo "Installing systemd service..."
    install -m 644 "$SCRIPT_DIR/cpu-profile-switch.service" /etc/systemd/system/cpu-profile-switch.service

    echo "Installing TLP config..."
    install -m 644 "$SCRIPT_DIR/tlp-quietcore.conf" /etc/tlp.d/01-quietcore.conf
}

configure_usb() {
    echo ""
    echo "USB device configuration"
    echo "------------------------"
    echo "quietcore prevents autosuspend on audio and Bluetooth by default."
    echo "You can also protect specific USB devices (keyboards, receivers, etc.)."
    echo ""
    echo "Connected USB devices:"
    lsusb | grep -v "root hub" | awk '{print "  " $6 "  " substr($0, index($0,$7))}'
    echo ""
    read -rp "Enter device IDs to protect (space-separated, e.g. 046d:c548 3554:fa09), or press enter to skip: " ids
    if [[ -n "$ids" ]]; then
        sed -i "s/^USB_DENYLIST=\"\"/USB_DENYLIST=\"$ids\"/" /etc/tlp.d/01-quietcore.conf
        echo "Added to denylist: $ids"
    fi
}

enable_services() {
    echo ""
    echo "Reloading TLP..."
    tlp start

    echo "Enabling and starting cpu-profile-switch..."
    systemctl daemon-reload
    systemctl enable --now cpu-profile-switch
}

print_status() {
    echo ""
    echo "Done. Current state:"
    echo "  profile : $(cat /sys/firmware/acpi/platform_profile)"
    echo "  turbo   : $(awk '{print ($1==0)?"on":"off"}' /sys/devices/system/cpu/intel_pstate/no_turbo)"
    echo "  epp     : $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)"
    echo ""
    echo "Watch live:"
    echo "  while true; do"
    echo "    echo \"profile: \$(cat /sys/firmware/acpi/platform_profile)\""
    echo "    echo \"turbo  : \$(awk '{print (\$1==0)?\"on\":\"off\"}' /sys/devices/system/cpu/intel_pstate/no_turbo)\""
    echo "    echo \"epp    : \$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference)\""
    echo "    awk '{printf \"temp   : %d C\\n\",\$1/1000}' \$(for z in /sys/class/thermal/thermal_zone*; do [[ \"\$(cat \$z/type)\" == \"x86_pkg_temp\" ]] && echo \$z/temp && break; done)"
    echo "    echo ---; sleep 1"
    echo "  done"
}

uninstall() {
    echo "Uninstalling quietcore..."
    systemctl disable --now cpu-profile-switch 2>/dev/null || true
    rm -f /usr/local/bin/cpu-profile-switch
    rm -f /usr/local/bin/quietcore
    rm -f /etc/systemd/system/cpu-profile-switch.service
    rm -f /etc/tlp.d/01-quietcore.conf
    systemctl daemon-reload
    tlp start
    echo "Done."
}

case "${1:-install}" in
    install)
        check_deps
        install_files
        configure_usb
        enable_services
        print_status
        ;;
    uninstall)
        uninstall
        ;;
    *)
        echo "Usage: sudo bash install.sh [install|uninstall]"
        exit 1
        ;;
esac
