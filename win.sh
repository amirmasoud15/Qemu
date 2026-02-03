#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# Project: Termux QEMU Pro Manager (Termux-X11 Edition)
# Version: 3.2.2 (Final Debugged)
# Description: Fixed memory parsing, CPU detection, and ISO selection logic.
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

# --- Resource Detection (Fixed Logic) ---
get_resources() {
    # Extracting total RAM in MB using free command
    TOTAL_RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
    
    # Fallback if detection fails
    if [[ ! "$TOTAL_RAM_MB" =~ ^[0-9]+$ ]]; then
        TOTAL_RAM_MB=2048
    fi

    # Safe allocation (50% of total)
    SAFE_RAM=$((TOTAL_RAM_MB / 2))
    
    # Boundary checks: Min 1GB, Max 8GB for stability
    if [ "$SAFE_RAM" -lt 1024 ]; then SAFE_RAM=1024; fi
    if [ "$SAFE_RAM" -gt 8192 ]; then SAFE_RAM=8192; fi
    
    # Accurate CPU Core detection
    CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo || echo 4)
}
get_resources

# --- Cleanup Trap ---
cleanup() {
    echo -e "\n${RED}[*] Stopping all processes...${NC}"
    pkill -f termux-x11
    pkill -f qemu-system-x86_64
    exit
}
trap cleanup SIGINT SIGTERM

# --- Utility Functions ---

banner() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║    QEMU PRO MANAGER (TERMUX-X11 v3.2)        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo -e "${BLUE}System   :${NC} ${CPU_CORES} Cores | ${TOTAL_RAM_MB}MB Total RAM"
    echo -e "${BLUE}VM Mem   :${NC} ${SAFE_RAM}MB Allocated"
    echo -e "------------------------------------------------"
}

show_system_status() {
    banner
    echo -e "${YELLOW}■ HARDWARE STATUS${NC}"
    echo -e "  Device     : $(getprop ro.product.model)"
    echo -e "  Android    : $(getprop ro.build.version.release)"
    echo -e "  Free Mem   : $(free -m | awk '/Mem:/ {print $4}') MB"
    echo ""
    echo -e "${YELLOW}■ STORAGE (HOME)${NC}"
    df -h "$HOME" | grep -v "Filesystem"
    echo ""
    echo -e "${YELLOW}■ SOFTWARE VERSION${NC}"
    if command -v qemu-system-x86_64 &> /dev/null; then
        qemu-system-x86_64 --version | head -n 1
    else
        echo -e "${RED}QEMU is not installed yet.${NC}"
    fi
    echo -e "${CYAN}==============================================${NC}"
    read -p "Press Enter to continue..."
}

check_dependencies() {
    echo -e "${YELLOW}[*] Validating environment packages...${NC}"
    pkg update -y
    pkg install -y x11-repo termux-x11-repo
    
    REQUIRED_PKGS="qemu-system-x86-64 qemu-utils wget termux-tools termux-x11-headless virglrenderer-android"
    for pkg in $REQUIRED_PKGS; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            echo -e "${YELLOW}[+] Installing $pkg...${NC}"
            pkg install -y "$pkg"
        fi
    done

    mkdir -p "$BASE_DIR"
    if [ ! -f "$VIRTIO_ISO" ]; then
        echo -e "${YELLOW}[*] Downloading VirtIO Drivers (Stable)...${NC}"
        wget -c -O "$VIRTIO_ISO" "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
    fi
}

select_iso() {
    mapfile -t ISO_LIST < <(ls "$BASE_DIR"/*.iso 2>/dev/null | grep -v "virtio-win.iso")
    if [ ${#ISO_LIST[@]} -eq 0 ]; then echo "NONE"; return; fi
    
    echo -e "${YELLOW}Available ISO Files:${NC}" >&2
    for i in "${!ISO_LIST[@]}"; do echo -e "[$((i+1))] $(basename "${ISO_LIST[$i]}")" >&2; done
    read -p "Select number: " selection >&2
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#ISO_LIST[@]}" ]; then
        echo "${ISO_LIST[$((selection-1))]}"
    else
        echo "INVALID"
    fi
}

launch_vm() {
    MODE=$1
    banner
    check_dependencies
    
    if [ ! -f "$DISK_IMG" ]; then
        echo -e "${YELLOW}[*] No disk found. Creating 40GB virtual drive...${NC}"
        qemu-img create -f qcow2 "$DISK_IMG" 40G
    fi
    
    SELECTED_ISO=$(select_iso)
    if [ "$SELECTED_ISO" == "NONE" ] && [ "$MODE" == "install" ]; then
        echo -e "${RED}[!] Error: No ISO found in $BASE_DIR. Please download or import one first.${NC}"
        read -p "Press Enter..."; return
    fi
    
    if [ "$SELECTED_ISO" == "INVALID" ]; then
        echo -e "${RED}[!] Invalid selection. Please try again.${NC}"
        sleep 1; return
    fi

    echo -e "${YELLOW}[*] Starting Termux-X11 Server...${NC}"
    pkill -f termux-x11
    termux-x11 :0 -ac > /dev/null 2>&1 &
    
    # Wait for X11 socket
    for i in {1..10}; do
        if [ -S "/tmp/.X11-unix/X0" ] || [ -S "$PREFIX/tmp/.X11-unix/X0" ]; then break; fi
        sleep 1
    done

    export DISPLAY=:0
    export GALLIUM_DRIVER=virpipe
    export VIRGL_NO_COHERENT=1

    BOOT_ORDER=$([ "$MODE" == "install" ] && echo "d" || echo "c")

    echo -e "${GREEN}[+] VM Initialized.${NC}"
    echo -e "${CYAN}[!] ACTION: Switch to Termux-X11 App to view Windows.${NC}"
    
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
    echo -e "1) ${GREEN}Run Windows${NC} (Normal Boot)"
    echo -e "2) ${YELLOW}Install Windows${NC} (ISO Boot)"
    echo -e "3) Manage Storage (Download/Import)"
    echo -e "4) Hardware Status"
    echo -e "5) Terminal Shell"
    echo -e "0) Exit"
    echo -e "------------------------------------------------"
    read -p "Choice: " main_opt

    case $main_opt in
        1) launch_vm "boot" ;;
        2) launch_vm "install" ;;
        3) 
            banner
            echo "1) Import ISO from Phone Storage (Downloads)"
            echo "2) Custom Download Link"
            read -p "Select: " ic
            if [ "$ic" == "1" ]; then
                termux-setup-storage
                echo -e "${YELLOW}[*] Scanning for .iso files in Downloads...${NC}"
                cp -v /sdcard/Download/*.iso "$BASE_DIR/" 2>/dev/null || echo -e "${RED}No ISO files found in /sdcard/Download${NC}"
                sleep 2
            elif [ "$ic" == "2" ]; then
                read -p "Enter direct link: " link
                wget -c -P "$BASE_DIR" "$link"
            fi
            ;;
        4) show_system_status ;;
        5) cd "$BASE_DIR" && bash ;;
        0) cleanup ;;
        *) sleep 1 ;;
    esac
done
