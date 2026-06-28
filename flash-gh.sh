#!/bin/bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NICENANO_VOLUME="/Volumes/NICENANO"
ARTIFACTS_DIR="$ROOT/build/gh-artifacts"

wait_and_flash() {
    local uf2=$1
    echo ""
    echo "Put the keyboard half into bootloader mode."
    echo "Waiting for NICENANO drive..."
    while [ ! -d "$NICENANO_VOLUME" ]; do
        sleep 1
    done
    sleep 1

    echo "==> Flashing $(basename "$uf2")..."
    cp "$uf2" "$NICENANO_VOLUME/"
    sync
    echo "==> Done."
}

if [ "$1" = "--from-file" ]; then
    if [ -z "$2" ]; then
        echo "Usage: ./flash-gh.sh --from-file <path/to/file.uf2>"
        exit 1
    fi
    wait_and_flash "$2"
    exit 0
fi

if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI (gh) is required. Install with: brew install gh"
    exit 1
fi

SKIP_PUSH=false
if [ "$1" = "--skip-push" ]; then
    SKIP_PUSH=true
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)

if [ "$SKIP_PUSH" = true ]; then
    echo "==> Triggering workflow on branch $BRANCH..."
    TRIGGERED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    gh workflow run build.yml --repo "$REPO" --ref "$BRANCH"
    COMMIT_SHA=$(git -C "$ROOT" rev-parse HEAD)

    echo "==> Waiting for Actions run to start..."
    RUN_ID=""
    for i in $(seq 1 30); do
        RUN_ID=$(gh run list --repo "$REPO" --branch "$BRANCH" --workflow "build.yml" --json databaseId,createdAt --jq "[.[] | select(.createdAt >= \"$TRIGGERED_AT\")] | .[0].databaseId" 2>/dev/null || true)
        [ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ] && break
        sleep 2
    done
else
    if ! git -C "$ROOT" diff --quiet || ! git -C "$ROOT" diff --cached --quiet; then
        echo "Error: uncommitted changes. Commit or stash them first."
        exit 1
    fi

    echo "==> Pushing to remote..."
    git -C "$ROOT" push

    COMMIT_SHA=$(git -C "$ROOT" rev-parse HEAD)

    echo "==> Waiting for Actions run to start..."
    RUN_ID=""
    for i in $(seq 1 30); do
        RUN_ID=$(gh run list --repo "$REPO" --commit "$COMMIT_SHA" --workflow "build.yml" --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)
        [ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ] && break
        sleep 2
    done
fi

if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "null" ]; then
    echo "Error: no Actions run found for commit $COMMIT_SHA"
    exit 1
fi

echo "==> Watching run $RUN_ID..."
gh run watch "$RUN_ID" --repo "$REPO"

CONCLUSION=$(gh run view "$RUN_ID" --repo "$REPO" --json conclusion -q .conclusion)
if [ "$CONCLUSION" != "success" ]; then
    echo "Error: build $CONCLUSION"
    exit 1
fi

echo "==> Downloading artifacts..."
rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"
gh run download "$RUN_ID" --repo "$REPO" --dir "$ARTIFACTS_DIR"

LEFT_UF2=$(find "$ARTIFACTS_DIR" -path "*left*" -name "*.uf2" | head -1)
RIGHT_UF2=$(find "$ARTIFACTS_DIR" -path "*right*" -name "*.uf2" | head -1)

if [ -z "$LEFT_UF2" ] || [ -z "$RIGHT_UF2" ]; then
    echo "Could not auto-detect left/right .uf2 files. Found:"
    find "$ARTIFACTS_DIR" -name "*.uf2"
    exit 1
fi

echo ""
echo "Which half do you want to flash?"
echo "  1) Left"
echo "  2) Right"
echo "  3) Both (left first, then right)"
read -rp "Choice [1/2/3]: " choice

case $choice in
    1) wait_and_flash "$LEFT_UF2" ;;
    2) wait_and_flash "$RIGHT_UF2" ;;
    3)
        wait_and_flash "$LEFT_UF2"
        wait_and_flash "$RIGHT_UF2"
        ;;
    *) echo "Invalid choice."; exit 1 ;;
esac
