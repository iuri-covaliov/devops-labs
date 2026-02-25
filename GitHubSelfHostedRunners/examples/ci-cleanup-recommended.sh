#!/usr/bin/env bash
set -euo pipefail

# Recommended cleanup for a self-hosted CI runner.
# Safe defaults: removes stopped containers, dangling images, unused networks, and build cache.
# Does NOT remove all unused images (so base images can stay and speed up builds).

echo "[ci-cleanup] Starting recommended cleanup..."

if ! command -v docker >/dev/null 2>&1; then
  echo "[ci-cleanup] ERROR: docker not found in PATH"
  exit 1
fi

echo "[ci-cleanup] Before:"
docker system df || true

echo "[ci-cleanup] Pruning stopped containers..."
docker container prune -f

echo "[ci-cleanup] Pruning dangling images..."
docker image prune -f

echo "[ci-cleanup] Pruning unused networks..."
docker network prune -f

echo "[ci-cleanup] Pruning build cache (BuildKit/builder)..."
docker builder prune -f

echo "[ci-cleanup] After:"
docker system df || true
df -h || true

echo "[ci-cleanup] Done."
