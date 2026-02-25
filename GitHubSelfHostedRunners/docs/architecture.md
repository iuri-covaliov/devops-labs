# Architecture — Self-Hosted GitHub Actions Runners

## Context

This lab explores running GitHub Actions workloads on a self-managed Linux server instead of GitHub-hosted runners.

The goal is to understand runner scope, lifecycle management, scheduling behavior, and how multiple runners can coexist on a single host.

---

## Runner Scopes

GitHub supports different runner scopes:

- **Repository-level runner**
  - Bound to a single repository
  - Simplest setup
  - Strong isolation by default (only one repo can use it)

- **Organization-level runner**
  - Shared across repositories inside an organization
  - Centralized management
  - Can be restricted using runner groups

A personal GitHub account does not support a “global runner” across all personal repositories.
Creating an organization enables shared runner infrastructure.

---

## Topologies

### Topology A — Repository-Only

```
Repository
↓
GitHub Actions
↓
Self-hosted runner
↓
Linux server
```

Use case:
- Single project
- Maximum isolation
- Minimal sharing

---

### Topology B — Mixed Setup (Current Lab)

```
GitHub Organization
↓
Org-level runner (systemd)
↓
Linux server

Personal Repository
↓
Repo-level runner (systemd)
↓
Same Linux server
```

Characteristics:
- Multiple runners on one host
- Explicit scope separation
- Label-based scheduling

---

## Host Layout

All runners live under:
```
/opt/gh-actions-runners/
```

Example:
```
/opt/gh-actions-runners/
├── personal-runner-1/
└── organization-runner-1/
```

Design rule:

One runner instance = one directory = one systemd service.

Each runner has:
- Its own `.runner` configuration file
- Its own credentials
- Its own systemd unit
- Independent lifecycle

---

## Scheduling Model

Scheduling is controlled by labels.

Example label strategy:

Personal runner:
- self-hosted
- linux
- personal

Organization runner:
- self-hosted
- linux
- org
- ci

Example targeting:

runs-on: [self-hosted, linux, personal]

runs-on: [self-hosted, linux, org, ci]

Avoid broad selectors like:

runs-on: [self-hosted, linux]

This may unintentionally match multiple runners.

---

## Operational Considerations

- Each runner installs its own systemd service.
- Multiple runners share CPU, RAM, and disk.
- Jobs may execute concurrently.
- Capacity depends on available resources.

If workloads grow:
- Add more runners
- Move runners to separate hosts
- Introduce container-based isolation
- Consider ephemeral runners

### Docker Installation on Ubuntu

Installing Docker via Snap can introduce filesystem confinement issues.

If the runner workspace lives under `/opt`, Snap-managed Docker may fail to access it, resulting in errors like:
```
lstat /var/lib/snapd/void/... no such file or directory
```

Using the apt-installed Docker (`docker.io`) avoids this issue.

---

## Security Notes

Self-hosted runners execute workflow code directly on the host.

Key implications:

- Repository-level runners limit exposure.
- Organization-level runners increase flexibility but widen execution scope.
- Labels should be explicit and intentional.
- Runner groups can restrict which repositories can use a shared runner.

### Runner Groups and Public Repositories

Organization runner groups do not allow public repositories by default.

If a repository is public and this option is disabled, workflows may remain in a waiting state even when the runner is online.

Runner group configuration must explicitly allow public repositories when needed.

---

## Future Directions

- Ephemeral runners per job
- Containerized job execution
- Resource isolation (cgroups)
- Autoscaling runners
