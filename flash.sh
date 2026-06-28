#!/bin/bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_IMAGE="zmkfirmware/zmk-build-arm:stable"
NICENANO_VOLUME="/Volumes/NICENANO"

run_in_docker() {
    docker run --rm \
        -v "$ROOT:/workspace" \
        -w /workspace \
        "$DOCKER_IMAGE" \
        bash -c "$1"
}

setup_workspace() {
    echo "==> Setting up ZMK workspace (first time, may take a while)..."
    run_in_docker "west init -l config && west update && west zephyr-export"
}

build() {
    local name=$1
    local shield=$2
    local extra=${3:-""}

    echo "==> Building $name..."
    docker run --rm \
        -v "$ROOT:/workspace" \
        -w /workspace \
        "$DOCKER_IMAGE" \
        bash -c "
            west zephyr-export && \
            west build -s zmk/app -b nice_nano_v2 \
                --build-dir build/$name \
                ${extra:+--snippet $extra} \
                -- \
                -DSHIELD='$shield' \
                -DZMK_CONFIG=/workspace/config \
                ${extra:+-DCONFIG_ZMK_STUDIO=y -DCONFIG_ZMK_STUDIO_LOCKING=n}
        "
}

wait_and_flash() {
    local uf2=$1

    echo ""
    echo "Put the keyboard half into bootloader mode (double-tap reset or use the bootloader key)."
    echo "Waiting for NICENANO drive..."

    while [ ! -d "$NICENANO_VOLUME" ]; do
        sleep 1
    done
    sleep 1

    echo "==> Drive found, flashing..."
    cp "$uf2" "$NICENANO_VOLUME/"
    sync
    echo "==> Done."
}

if [ "$1" = "clean" ]; then
    echo "==> Cleaning build directories..."
    rm -rf "$ROOT/build/left" "$ROOT/build/right"
fi

if [ ! -d "$ROOT/.west" ]; then
    setup_workspace
fi

build "left"  "eyelash_sofle_left nice_view"  "studio-rpc-usb-uart"
build "right" "eyelash_sofle_right nice_view"

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
