# Architecture

This lab is intentionally structured as a migration: we start with a working deployment and then reduce trust.

## Phase 1 — Static credentials

**Control flow**
1. GitHub Actions workflow starts.
2. Workflow loads long‑lived AWS credentials from GitHub Secrets.
3. Workflow calls AWS APIs directly (S3 upload).

**Trust model**
- Secrets are long‑lived.
- Anyone who can access repo secrets (or exfiltrate them via a misconfiguration) can access AWS until the keys are rotated.
- Rotation is manual work (and often delayed).

**Why we still do this in Phase 1**
- It gives a baseline that is easy to understand and validate.
- It makes the security improvement in Phase 2 concrete: same deploy, less trust.

## Phase 2 — OIDC federation

**Control flow**
1. GitHub Actions workflow starts.
2. Workflow requests a signed OIDC token from GitHub’s OIDC provider (`token.actions.githubusercontent.com`).
3. AWS IAM validates the token via an **OIDC identity provider** configured in your account.
4. AWS STS issues **temporary credentials** when the workflow assumes an **IAM role** (`sts:AssumeRoleWithWebIdentity`).
5. Workflow uses the temporary credentials to upload to S3.

**Trust model**
- No long‑lived AWS keys are stored in GitHub.
- Role assumption can be scoped to:
  - the exact repo (`sub` claim)
  - optionally the branch (`refs/heads/main`)
  - optionally the GitHub environment
- Credentials are short‑lived and expire automatically.

## Diagram placeholders

- `docs/images/phase1.png` — GitHub Secrets → IAM user → S3
- `docs/images/phase2.png` — OIDC token → IAM OIDC provider → STS → role → S3
- `docs/images/final.png` — Final state + optional ECR/ECS branch

(We’ll generate these after the runbook is finalized so the labels match the final resource names.)
