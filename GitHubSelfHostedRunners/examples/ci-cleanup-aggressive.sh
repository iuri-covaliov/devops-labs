#!/usr/bin/env bash
set -euo pipefail

# Aggressive cleanup for a self-hosted CI runner.
# WARNING: This removes ALL unused images, ALL stopped containers, ALL unused networks,
# and ALL build cache. Builds will likely be slower next time due to re-pulls and re-builds.

echo "[ci-cleanup] Starting AGGRESSIVE cleanup..."

if ! command -v docker >/dev/null 2>&1; then
  echo "[ci-cleanup] ERROR: docker not found in PATH"
  exit 1
fi

echo "[ci-cleanup] Before:"
docker system df || true

echo "[ci-cleanup] Running: docker system prune -af"
docker system prune -af

# Optional: also remove unused volumes (can be large). Uncomment if desired.
# echo "[ci-cleanup] Running: docker volume prune -f"
# docker volume prune -f

echo "[ci-cleanup] After:"
docker system df || true
df -h || true

echo "[ci-cleanup] Done."
