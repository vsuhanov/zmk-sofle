#!/bin/bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_IMAGE="zmkfirmware/zmk-build-arm:stable"
NICENANO_VOLUME="/Volumes/NICENANO"

setup_workspace() {
    echo "==> Setting up ZMK workspace (first time, may take a while)..."
    docker run --rm \
        -v "$ROOT:/workspace" \
        -w /workspace \
        "$DOCKER_IMAGE" \
        bash -c "west init -l config && west update && west zephyr-export"
}

build_all() {
    echo "==> Building left and right..."
    docker run --rm \
        -v "$ROOT:/workspace" \
        -w /workspace \
        "$DOCKER_IMAGE" \
        bash -c "
            west build -s zmk/app -b nice_nano_v2 \
                --build-dir build/left \
                --snippet studio-rpc-usb-uart \
                -- \
                -DSHIELD='eyelash_sofle_left nice_view' \
                -DZMK_CONFIG=/workspace/config \
                -DCONFIG_ZMK_STUDIO=y \
                -DCONFIG_ZMK_STUDIO_LOCKING=n && \
            west build -s zmk/app -b nice_nano_v2 \
                --build-dir build/right \
                -- \
                -DSHIELD='eyelash_sofle_right nice_view' \
                -DZMK_CONFIG=/workspace/config
        "
}

wait_and_flash() {
    local uf2=$1
    local mount_point

    echo ""
    echo "Put the keyboard half into bootloader mode (double-tap reset or use the bootloader key)."
    echo "Waiting for NICENANO drive..."

    while true; do
        mount_point=$(mount | awk '/NICENANO/ {print $3}' | head -1)
        [ -n "$mount_point" ] && break
        sleep 1
    done
    sleep 1

    echo "==> Drive found, flashing..."
    cp "$uf2" "$mount_point/"
    sync
    echo "==> Done."

    while mount | grep -q "NICENANO"; do
        sleep 1
    done
}

if [ "$1" = "clean" ]; then
    echo "==> Cleaning build directories..."
    rm -rf "$ROOT/build/left" "$ROOT/build/right"
fi

if [ ! -d "$ROOT/.west" ]; then
    setup_workspace
fi

build_all

echo ""
echo "Which half do you want to flash?"
echo "  1) Left"
echo "  2) Right"
echo "  3) Both (left first, then right)"
read -rp "Choice [1/2/3]: " choice

case $choice in
    1) wait_and_flash "$ROOT/build/left/zephyr/zmk.uf2" ;;
    2) wait_and_flash "$ROOT/build/right/zephyr/zmk.uf2" ;;
    3)
        wait_and_flash "$ROOT/build/left/zephyr/zmk.uf2"
        wait_and_flash "$ROOT/build/right/zephyr/zmk.uf2"
        ;;
    *) echo "Invalid choice."; exit 1 ;;
esac
