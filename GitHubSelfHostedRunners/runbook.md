# Runbook — Self-hosted GitHub Actions Runners on Linux Server (Ubuntu 24.04)

This runbook builds a practical self-hosted GitHub Actions runner setup on a Linux server.

- **Phase 1 — Personal repo runner:** One repository-bound runner, started manually.
- **Phase 2 — Organization runner:** Run the runner as a `systemd` service, and (optionally) register it at **Organization** scope so multiple repositories can use it via labels.

> Notes
> - Commands assume **Ubuntu 24.04** and a non-root SSH user with `sudo`.
> - Use placeholders consistently: `<RUNNER_USER>`, `<RUNNER_ROOT>`, `<ORG_OR_REPO_URL>`, `<RUNNER_NAME>`, `<LABELS>`.
> - GitHub’s UI provides the exact download URL and registration token. This runbook shows the structure and verification steps.

---

## Directory Structure (Multi-Runner Design)

All runners live under a single root directory:

```
/opt/gh-actions-runners/
├── personal-runner-1/
└── organization-runner-1/
```

Each runner:
- Has its own directory
- Has its own .runner configuration file
- Installs its own systemd service
- Runs independently

Never configure two runners in the same directory.

---

## Prerequisites

### Accounts and permissions
- GitHub repository where you can add a self-hosted runner (repo admin), and optionally:
- A GitHub **Organization** (you can create one) where you can add self-hosted runners (org owner/admin).

### Server requirements
- Ubuntu 24.04 server reachable over SSH
- Recommended: 2 vCPU / 4 GB RAM minimum for typical CI workloads
- Outbound internet access (to download the runner and fetch dependencies)
- Inbound ports: **not required** for the runner itself (it polls GitHub outbound)

---

### Server packages
Install a few utilities:

```bash
sudo apt-get update
sudo apt-get install -y curl tar gzip ca-certificates jq
```

Expected result:
- Packages install without errors.

---

### Docker Installation (Recommended)

Avoid installing Docker via Snap on Ubuntu, as Snap confinement can prevent Docker from accessing the runner workspace under `/opt`.

Install Docker via apt:

```bash
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
```

Verify:
```
which docker
systemctl status docker --no-pager
```

Expected:
```
Docker binary at /usr/bin/docker
...
Service active (running)
```

---

## Convention used in this runbook

Set a few variables (edit values as needed):

```bash
export RUNNER_USER="ghactions"
export RUNNER_ROOT="/opt/gh-actions-runners"
export PERSONAL_RUNNER_NAME="personal-runner-1"
export PERSONAL_REPO_URL="<PERSONAL_REPO_URL>"
export PERSONAL_RUNNER_DIR="$RUNNER_ROOT/$PERSONAL_RUNNER_NAME"
export PERSONAL_LABELS="linux,x64,personal"
export ORG_RUNNER_NAME="organization-runner-1"
export ORG_URL="<ORG_URL>"
export ORG_RUNNER_DIR="$RUNNER_ROOT/$ORG_RUNNER_NAME"
export ORG_LABELS="linux,x64,org,ci"
```

Expected result:
- No output (exports succeed).

---

### Create a dedicated runner user and directory

Create a locked-down system user:

```bash
sudo useradd --create-home --shell /bin/bash "$RUNNER_USER" || true
```


Create the runner directory:

```bash
sudo mkdir -p "$RUNNER_ROOT"
sudo chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_ROOT"
```


---

## Phase 1 — Personal Repo Runner

### 1) Create personal runner directory

```
sudo mkdir -p "$PERSONAL_RUNNER_DIR"
sudo chown -R "$RUNNER_USER:$RUNNER_USER" "$PERSONAL_RUNNER_DIR"
```

Verify:
```
ls -ld "$PERSONAL_RUNNER_DIR"
```

---

### 2) Download and extract runner

**In GitHub**:

Repository → Settings → Actions → Runners → New self-hosted runner → Linux

Save the token for registering the runner.
```
export PERSONAL_RUNNER_TOKEN=<TOKEN>
```

Then **on the server**:
```
sudo -u "$RUNNER_USER" -H bash -lc "cd '$PERSONAL_RUNNER_DIR' && curl -fsSL -o actions-runner.tar.gz <RUNNER_TAR_GZ_URL> && tar xzf actions-runner.tar.gz && rm actions-runner.tar.gz"
```
Verify:
```
sudo -u "$RUNNER_USER" -H bash -lc "test -x '$PERSONAL_RUNNER_DIR/config.sh' && echo OK"
```

---

### 3) Register to Personal Repository

```
sudo -u "$RUNNER_USER" -H bash -lc "cd '$PERSONAL_RUNNER_DIR' && ./config.sh --url $PERSONAL_REPO_URL --token $PERSONAL_RUNNER_TOKEN --name '$PERSONAL_RUNNER_NAME' --labels '$PERSONAL_LABELS' --unattended"
```

Expected:
Runner appears in repository UI as Idle.

Local verification:

```bash
sudo -u "$RUNNER_USER" -H bash -lc "cd '$PERSONAL_RUNNER_DIR' && ./config.sh --help >/dev/null && echo Registered"
```

---

### 4) Start the runner manually

```bash
sudo -u "$RUNNER_USER" -H bash -lc "cd '$PERSONAL_RUNNER_DIR' && ./run.sh"
```

Expected result:
- You see logs indicating the runner connected and is listening for jobs.
- Leave this terminal open during Phase 1 tests.

Quick local check (in a **second** SSH session):

```bash
ps -ef | grep -E "Runner\.Listener|run\.sh" | grep -v grep
```

Expected result:
- A process for the runner is visible.

---

### 5) Test with a minimal workflow

In your repository, add `.github/workflows/workflow-smoke-personal.yml`:

```yaml
name: self-hosted-smoke

on:
  workflow_dispatch:

jobs:
  smoke:
    runs-on: [self-hosted, linux, x64, personal]
    steps:
      - name: Who am I
        run: |
          whoami
          uname -a
          lsb_release -a || true
      - name: Disk and memory
        run: |
          df -h
          free -h
```

Trigger it from GitHub: **Actions → self-hosted-smoke → Run workflow**.

Expected result:
- Job runs on your server.
- The `whoami` output matches `<RUNNER_USER>` (often `actions`).
- Runner terminal shows the job being executed.

---

### 6) Stop the manual runner

When done with Phase 1:

- Press `Ctrl+C` in the terminal running `./run.sh`.

Expected result:
- Runner stops listening.

---

### 7) [Optionally] Install as service

```
sudo bash -lc "cd '$PERSONAL_RUNNER_DIR' && ./svc.sh install '$RUNNER_USER'"
sudo bash -lc "cd '$PERSONAL_RUNNER_DIR' && ./svc.sh start"
```
Verify:
```
systemctl list-units | grep actions.runner
```
stop:
```
sudo bash -lc "cd '$PERSONAL_RUNNER_DIR' && ./svc.sh stop"
```

---

## Phase 2 — Organization Runner (Shared Runner)

Phase 2 has two improvements:
1) Make runner lifecycle reliable: run as a service (auto-start on boot).
2) Reduce repo-coupling: optionally register runner at **Organization** scope and target via labels.

### 1) Create organization runner directory

```
sudo mkdir -p "$ORG_RUNNER_DIR"
sudo chown -R "$RUNNER_USER:$RUNNER_USER" "$ORG_RUNNER_DIR"
```

---

### 2) Download runner

Organization → Settings → Actions → Runners → New runner -> New self-hosted runner → Linux

Save the runner's token and tar.gz URL for registering the runner:
```
export ORG_RUNNER_TOKEN=<TOKEN>
export ORG_RUNNER_TAR_GZ_URL=<RUNNER_TAR_GZ_URL>
```

Download and extract:
```
sudo -u "$RUNNER_USER" -H bash -lc "cd '$ORG_RUNNER_DIR' && curl -fsSL -o actions-runner.tar.gz $ORG_RUNNER_TAR_GZ_URL && tar xzf actions-runner.tar.gz && rm actions-runner.tar.gz"
```

---

### 3) Register at Organization Scope

```
sudo -u "$RUNNER_USER" -H bash -lc "cd '$ORG_RUNNER_DIR' && ./config.sh --url $ORG_URL --token '$ORG_RUNNER_TOKEN' --name '$ORG_RUNNER_NAME' --labels '$ORG_LABELS' --unattended"
```
---

### 4) Install the runner as a systemd service

From the runner directory:

```bash
sudo bash -lc "cd '$ORG_RUNNER_DIR' && ./svc.sh install '$RUNNER_USER'"
sudo bash -lc "cd '$ORG_RUNNER_DIR' && ./svc.sh start"
sudo bash -lc "cd '$ORG_RUNNER_DIR' && ./svc.sh status"
```

Expected result:
- Status shows the service as running.

Verify with systemd:

```bash
systemctl status "actions.runner.*" --no-pager || true
```

> If you have multiple runners installed, you’ll see multiple matching units.

Reboot verification (important):

```bash
sudo reboot
```

After reconnecting:

```bash
sudo bash -lc "cd '$ORG_RUNNER_DIR' && ./svc.sh status"
```

Expected result:
- Service is running without manual start.

---

### 5) Target the shared runner via labels

Update workflows in org repositories to target labels you control.

Example:

```yaml
runs-on: [self-hosted, linux, x64, ci]
```

If you added `org-shared`, you can require it:

```yaml
runs-on: [self-hosted, linux, x64, org-shared]
```

Expected result:
- Jobs schedule only onto runners with those labels.

---

### 6) Runner groups (optional governance)

If you share runners across multiple repositories, use **Runner groups**:
- Org → Settings → Actions → Runner groups
- Create a group (e.g., `shared-ci`)
- Restrict which repositories can use it
- Add your runner(s) to the group

Expected result:
- Only allowed repositories can schedule jobs onto the runner group.

---

## Validation checklist

Run through this after Phase 2:

- [ ] Runner service is active: `./svc.sh status` shows running
- [ ] Runner survives reboot and returns to **Idle**
- [ ] A test workflow completes successfully using label targeting
- [ ] Logs are readable:
  - `journalctl -u "actions.runner.*" -n 200 --no-pager` shows recent activity
- [ ] (If org-level) runner is visible at org scope and used by at least 2 repos
- [ ] (If runner groups) only permitted repos can use the runner

---

## Troubleshooting

### Symptom: Runner shows “Offline” in GitHub UI
Likely causes:
- Service not running
- Network egress blocked
- Runner crashed

Fix:
```bash
sudo bash -lc "cd '$ORG_RUNNER_DIR' && ./svc.sh status || true"
sudo bash -lc "cd '$ORG_RUNNER_DIR' && ./svc.sh restart"
journalctl -u "actions.runner.*" -n 200 --no-pager || true
```

---

### Symptom: Workflow stuck in “Waiting for a runner”
Likely causes:
- `runs-on` labels don’t match runner labels
- Runner is busy
- Runner group restrictions block the repo

Fix:
- In GitHub runner page, check runner labels.
- Ensure workflow has at least `self-hosted` and the labels you actually set.
- If using runner groups, confirm the repo is allowed.
- If repository is public, confirm that the runner group allows public repositories:
  Organization → Settings → Actions → Runner groups → Enable "Allow public repositories"

---

### Symptom: `./svc.sh install` fails or service won’t start
Likely causes:
- Wrong runner directory permissions
- Runner configured but service unit points to wrong user
- Incomplete runner installation

Fix:
```bash
ls -ld "$ORG_RUNNER_DIR"
sudo chown -R "$RUNNER_USER:$RUNNER_USER" "$ORG_RUNNER_DIR"
sudo bash -lc "cd '$ORG_RUNNER_DIR' && ./svc.sh uninstall || true"
sudo bash -lc "cd '$ORG_RUNNER_DIR' && ./svc.sh install '$RUNNER_USER'"
sudo bash -lc "cd '$ORG_RUNNER_DIR' && ./svc.sh start"
```

---

### Symptom: Jobs fail because tools are missing (git, node, docker, etc.)
Likely causes:
- Self-hosted runner images are “empty” compared to GitHub-hosted runners

Fix:
- Install required dependencies on the server, or
- Run jobs in containers, or
- Use a provisioning script and document it in `provision/`

Quick check inside a job:
```bash
which git node docker || true
```

---

## Cleanup / rollback

### Remove the runner from GitHub and the server

1) Stop service:
```bash
sudo bash -lc "cd '$ORG_RUNNER_DIR' && ./svc.sh stop"
```

2) Remove registration (needs a remove token from GitHub UI):
```bash
sudo -u "$RUNNER_USER" -H bash -lc "cd '$ORG_RUNNER_DIR' && ./config.sh remove --token <REMOVE_TOKEN>"
```

3) Uninstall service:
```bash
sudo bash -lc "cd '$ORG_RUNNER_DIR' && ./svc.sh uninstall"
```

4) Delete files (optional):
```bash
sudo rm -rf "$ORG_RUNNER_DIR"
sudo userdel -r "$RUNNER_USER" || true
```

Expected result:
- Runner disappears from GitHub UI and no service remains on the server.

---

## Appendix — Useful commands

Service logs:
```bash
journalctl -u "actions.runner.*" -n 200 --no-pager
```

Runner status:
```bash
sudo bash -lc "cd '$ORG_RUNNER_DIR' && ./svc.sh status"
```

See runner labels in local config:
```bash
sudo -u "$RUNNER_USER" -H bash -lc "cat '$ORG_RUNNER_DIR/.runner' | jq . || true"
```
