#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# Project: Termux QEMU Pro Manager (Termux-X11 Edition)
# Version: 3.1.0 (Debugged & Optimized)
# Description: Fixed process handling, improved RAM logic, and GPU paths
# ==============================================================================

# --- Configuration & Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Paths
BASE_DIR="$HOME/qemu-pro"
DISK_IMG="$BASE_DIR/windows.qcow2"
VIRTIO_ISO="$BASE_DIR/virtio-win.iso"

# State Flags
DEPS_CHECKED=false

# --- Resource Detection ---
get_resources() {
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
    
    # اختصاص ۵۰٪ رم، اما نه کمتر از ۱ گیگ و نه بیشتر از ۸ گیگ برای پایداری
    SAFE_RAM=$((TOTAL_RAM_MB / 2))
    if [ $SAFE_RAM -lt 1024 ]; then SAFE_RAM=1024; fi
    
    CPU_CORES=$(nproc)
}
get_resources

# --- Cleanup Trap ---
cleanup() {
    echo -e "\n${RED}[*] Cleaning up processes...${NC}"
    pkill -f termux-x11
    pkill -f qemu-system-x86_64
    exit
}
trap cleanup SIGINT SIGTERM

# --- Utility Functions ---

banner() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║    QEMU PRO MANAGER (TERMUX-X11 v3.1)        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo -e "${BLUE}Host Info:${NC} ${CPU_CORES} Cores | ${TOTAL_RAM_MB}MB Total RAM"
    echo -e "${BLUE}VM Alloc :${NC} ${SAFE_RAM}MB RAM"
    echo -e "------------------------------------------------"
}

show_system_status() {
    banner
    echo -e "${YELLOW}■ SYSTEM INFORMATION${NC}"
    echo -e "  Device     : $(getprop ro.product.model)"
    echo -e "  Android    : $(getprop ro.build.version.release)"
    echo -e "  Available  : $(free -m | awk '/Mem:/ {print $4}') MB RAM"
    echo ""
    echo -e "${YELLOW}■ STORAGE INFO${NC}"
    df -h "$HOME" | grep -v "Filesystem"
    echo ""
    echo -e "${YELLOW}■ QEMU STATUS${NC}"
    qemu-system-x86_64 --version | head -n 1
    echo -e "${CYAN}==============================================${NC}"
    read -p "Press Enter to continue..."
}

check_dependencies() {
    if [ "$DEPS_CHECKED" = true ]; then return; fi
    echo -e "${YELLOW}[*] Validating environment...${NC}"
    
    # اطمینان از وجود مخازن صحیح
    pkg update -y
    pkg install -y x11-repo termux-x11-repo
    
    REQUIRED_PKGS="qemu-system-x86-64 qemu-utils wget termux-tools termux-x11-headless virglrenderer-android"
    for pkg in $REQUIRED_PKGS; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            echo -e "${YELLOW}[*] Installing $pkg...${NC}"
            pkg install -y "$pkg"
        fi
    done

    mkdir -p "$BASE_DIR"

    if [ ! -f "$VIRTIO_ISO" ]; then
        echo -e "${YELLOW}[*] Downloading VirtIO Drivers...${NC}"
        wget -c -O "$VIRTIO_ISO" "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
    fi
    
    DEPS_CHECKED=true
}

select_iso() {
    mapfile -t ISO_LIST < <(ls "$BASE_DIR"/*.iso 2>/dev/null | grep -v "virtio-win.iso")
    if [ ${#ISO_LIST[@]} -eq 0 ]; then echo "NONE"; return; fi
    
    echo -e "${YELLOW}Select ISO File:${NC}" >&2
    for i in "${!ISO_LIST[@]}"; do echo -e "[$((i+1))] $(basename "${ISO_LIST[$i]}")" >&2; done
    read -p "Selection: " selection >&2
    echo "${ISO_LIST[$((selection-1))]}"
}

# --- Core Execution ---

launch_vm() {
    MODE=$1
    banner
    check_dependencies
    
    if [ ! -f "$DISK_IMG" ]; then
        echo -e "${YELLOW}[*] Creating 40GB Virtual Disk...${NC}"
        qemu-img create -f qcow2 "$DISK_IMG" 40G
    fi
    
    SELECTED_ISO=$(select_iso)
    if [ "$SELECTED_ISO" == "NONE" ] && [ "$MODE" == "install" ]; then
        echo -e "${RED}[!] Error: No ISO found in $BASE_DIR${NC}"
        read -p "Press Enter..."; return
    fi

    # راه اندازی Termux-X11 با متغیرهای صحیح
    echo -e "${YELLOW}[*] Starting Termux-X11 Server...${NC}"
    pkill -f termux-x11 # بستن نمونه‌های قبلی برای جلوگیری از تداخل
    termux-x11 :0 -ac > /dev/null 2>&1 &
    
    # انتظار هوشمند برای بالا آمدن سرور
    for i in {1..10}; do
        if [ -S "/tmp/.X11-unix/X0" ] || [ -S "$PREFIX/tmp/.X11-unix/X0" ]; then break; fi
        sleep 1
    done

    export DISPLAY=:0
    # فعال سازی VirGL برای شتاب دهی گرافیکی
    export GALLIUM_DRIVER=virpipe
    export VIRGL_NO_COHERENT=1

    BOOT_ORDER=$([ "$MODE" == "install" ] && echo "d" || echo "c")

    echo -e "${GREEN}[+] VM Starting!${NC}"
    echo -e "${CYAN}[!] IMPORTANT: Open Termux-X11 App NOW.${NC}"
    
    # بهبود آرگومان‌های گرافیکی برای هماهنگی با Termux-X11
    qemu-system-x86_64 \
        -m "${SAFE_RAM}M" \
        -cpu max \
        -smp cores="$CPU_CORES",threads=1 \
        -device virtio-vga-gl \
        -display x11,gl=on \
        -drive file="$DISK_IMG",if=virtio,cache=writethrough \
        -drive file="$SELECTED_ISO",media=cdrom,readonly=on \
        -drive file="$VIRTIO_ISO",media=cdrom,readonly=on \
        -boot order="$BOOT_ORDER",menu=on \
        -net nic,model=virtio -net user \
        -rtc base=localtime,clock=host \
        -usb -device usb-tablet \
        -monitor stdio

    pkill -f termux-x11
}

# --- Main Menu ---

while true; do
    banner
    echo -e "1) ${GREEN}Run Windows${NC} (Normal)"
    echo -e "2) ${YELLOW}Install Windows${NC} (ISO Boot)"
    echo -e "3) Manage Files (Download/Import)"
    echo -e "4) System Status"
    echo -e "5) Terminal / Shell"
    echo -e "0) Exit"
    echo -e "------------------------------------------------"
    read -p "Option: " main_opt

    case $main_opt in
        1) launch_vm "boot" ;;
        2) launch_vm "install" ;;
        3) 
            banner
            echo "1) Import from /sdcard/Download"
            echo "2) Custom Download URL"
            read -p "Choice: " ic
            if [ "$ic" == "1" ]; then
                termux-setup-storage
                cp -v /sdcard/Download/*.iso "$BASE_DIR/" 2>/dev/null || echo "No ISO found in Downloads."
                sleep 2
            fi
            ;;
        4) show_system_status ;;
        5) cd "$BASE_DIR" && bash ;;
        0) cleanup ;;
        *) sleep 1 ;;
    esac
done