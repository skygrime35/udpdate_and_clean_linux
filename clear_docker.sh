#!/usr/bin/env bash
# cleardocker.sh
# Near-complete purge of everything managed by Docker (containers, images, volumes, custom networks, build cache)
# without uninstalling Docker itself.

set -euo pipefail

########################################
# Sanity checks
########################################

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: 'docker' command is not available (Docker not installed or not in PATH)." >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "Error: unable to communicate with Docker daemon (missing permissions? service stopped?)." >&2
    exit 1
fi

########################################
# Warning (non-interactif)
########################################

cat <<'EOF'
WARNING: this operation will attempt to DELETE:
  - All containers (running or stopped)
  - All local images
  - All Docker volumes
  - All custom Docker networks (excluding bridge/host/none)
  - Docker build cache
  - All unused resources via 'docker system prune -a --volumes'

Docker itself will NOT be uninstalled, but the environment will be reset to a "clean slate".

Proceeding WITHOUT interactive confirmation.
EOF

echo
echo ">>> Starting Docker purge..."
echo

########################################
# 1. Stop all running containers
########################################
echo "[1/7] Stopping all running containers..."
RUNNING_CONTAINERS="$(docker ps -q || true)"
if [ -n "$RUNNING_CONTAINERS" ]; then
    docker stop $RUNNING_CONTAINERS
else
    echo "    No running containers."
fi
echo

########################################
# 2. Remove all containers
########################################
echo "[2/7] Removing all containers (all states)..."
ALL_CONTAINERS="$(docker ps -aq || true)"
if [ -n "$ALL_CONTAINERS" ]; then
    docker rm -f $ALL_CONTAINERS
else
    echo "    No containers to remove."
fi
echo

########################################
# 3. Remove all images
########################################
echo "[3/7] Removing all local images..."
ALL_IMAGES="$(docker images -q || true)"
if [ -n "$ALL_IMAGES" ]; then
    docker rmi -f $ALL_IMAGES
else
    echo "    No images to remove."
fi
echo

########################################
# 4. Remove all volumes
########################################
echo "[4/7] Removing all Docker volumes..."
ALL_VOLUMES="$(docker volume ls -q || true)"
if [ -n "$ALL_VOLUMES" ]; then
    docker volume rm $ALL_VOLUMES
else
    echo "    No volumes to remove."
fi
echo

########################################
# 5. Remove custom networks
########################################
echo "[5/7] Removing custom Docker networks..."
# Exclude default networks: bridge, host, none
ALL_NETWORKS="$(docker network ls -q || true)"
CUSTOM_NETWORKS="$(docker network ls --format '{{.ID}} {{.Name}}' 2>/dev/null \
    | awk '$2 != "bridge" && $2 != "host" && $2 != "none" {print $1}' || true)"

if [ -n "$CUSTOM_NETWORKS" ]; then
    # shellcheck disable=SC2086
    docker network rm $CUSTOM_NETWORKS
else
    echo "    No custom networks to remove."
fi
echo

########################################
# 6. Prune build cache
########################################
echo "[6/7] Pruning Docker build cache..."
# -a: all cache, -f: no confirmation
docker builder prune -af || true
echo

########################################
# 7. Final cleanup with docker system prune
########################################
echo "[7/7] docker system prune -a --volumes (global cleanup)..."
docker system prune -a --volumes -f || true
echo

########################################
# Final state
########################################
echo ">>> Final Docker disk usage state:"
docker system df || true

echo
echo "Docker purge complete."