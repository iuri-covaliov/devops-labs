# CI Cleanup Scripts

This directory contains maintenance scripts for self-hosted GitHub
Actions runners.

Owning your CI means owning disk lifecycle. These scripts help control
Docker growth on the runner host.

------------------------------------------------------------------------

## 1. Recommended Cleanup

File: `ci-cleanup-recommended.sh`

Use for: - Weekly scheduled cleanup - Regular maintenance - CI hosts
where build speed matters

What it does: - Removes stopped containers - Removes dangling images -
Removes unused networks - Cleans BuildKit cache

What it does NOT do: - Does not remove all unused images - Does not wipe
everything aggressively

Run:

``` bash
bash ci-cleanup-recommended.sh
```

------------------------------------------------------------------------

## 2. Aggressive Cleanup

File: `ci-cleanup-aggressive.sh`

Use for: - Emergency disk recovery - Lab environments - Situations where
disk space is critically low

What it does: - Removes ALL unused images - Removes ALL stopped
containers - Removes ALL unused networks - Removes ALL build cache

Warning: Next builds will be slower because images and layers must be
pulled and rebuilt again.

Run:

``` bash
bash ci-cleanup-aggressive.sh
```

------------------------------------------------------------------------

## Suggested Automation

Example weekly cron job:

``` bash
0 3 * * 0 /path/to/ci-cleanup-recommended.sh >> /var/log/ci-cleanup.log 2>&1
```

This runs every Sunday at 03:00.

------------------------------------------------------------------------

## Operational Recommendation

Monitor regularly:

``` bash
docker system df
df -h
```

Self-hosted runners are persistent machines. Disk management is part of
operating CI infrastructure.
