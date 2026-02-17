# Runbook — GitHub Actions to AWS via OIDC (S3 baseline)

This runbook is designed to be reproducible from scratch.

- **Phase 1 — Make it work:** static AWS keys stored in GitHub Secrets (baseline).
- **Phase 2 — Reduce trust / Harden access:** GitHub OIDC → IAM role → short‑lived credentials (no stored AWS keys).

---

## Prerequisites

- An AWS account and permissions to manage IAM and S3 (admin is fine for the lab).
- AWS CLI v2 installed locally.
- A GitHub repository where you can create workflows.
- A local shell with `bash` and `jq`.

Recommended local setup checks:

```bash
aws --version
aws sts get-caller-identity
jq --version
```

Expected result:
- `aws sts get-caller-identity` prints your AWS account/user/role identity.

---

## Conventions and placeholders

Use these placeholders consistently:

- `<AWS_REGION>` — e.g. `us-east-1`
- `<AWS_ACCOUNT_ID>` — your 12-digit account id
- `<BUCKET_NAME>` — globally unique, e.g. `my-oidc-lab-<RANDOM>`
- `<GITHUB_OWNER>` — your GitHub username or org
- `<GITHUB_REPO>` — repository name
- `<ROLE_NAME>` — e.g. `GitHubActionsS3DeployRole`

Export them once (adjust values):

```bash
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export BUCKET_NAME="oidc-lab-${AWS_ACCOUNT_ID}-${AWS_REGION}"
export GITHUB_OWNER="<GITHUB_OWNER>"
export GITHUB_REPO="<GITHUB_REPO>"
export ROLE_NAME="GitHubActionsS3DeployRole"
```

Or you could add all those variables to the .env file and run:
```bash
source .env
```

Confirm:

```bash
echo "$AWS_REGION $AWS_ACCOUNT_ID $BUCKET_NAME $GITHUB_OWNER/$GITHUB_REPO $ROLE_NAME"
```

---

# Phase 1 — Make it work

Phase 1 is an intentionally over‑trusting baseline. We will store long‑lived AWS keys in GitHub Secrets.

## Step 1 — Create a minimal static site

Create files (or use your own). From your local machine:

```bash
mkdir -p examples/site
cat > examples/site/index.html <<'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>GitHub → AWS S3 Deploy (OIDC Lab)</title>
  </head>
  <body>
    <h1>It works.</h1>
    <p>This page was deployed by GitHub Actions.</p>
  </body>
</html>
HTML
```

Expected result:
- `examples/site/index.html` exists.

## Step 2 — Create the S3 bucket

Create the bucket:

```bash
aws s3api create-bucket   --bucket "$BUCKET_NAME"   --region "$AWS_REGION"   $( [ "$AWS_REGION" = "us-east-1" ] || echo "--create-bucket-configuration LocationConstraint=$AWS_REGION" )
```
> `$( [ "$AWS_REGION" = "us-east-1" ] || echo "--create-bucket-configuration LocationConstraint=$AWS_REGION" )` segment conditionally adds extra configuration. AWS S3 has a quirk: the us-east-1 region doesn't need (and will reject) the LocationConstraint parameter. All other regions require it to specify where the bucket should physically reside. This command handles both cases automatically, preventing errors in either scenario.

Enable static website hosting:

```bash
aws s3 website "s3://$BUCKET_NAME/" --index-document index.html
```

Expected result:
- Bucket exists and website config is set.

AWS -> S3 -> Buckets -> BUCKET_NAME -> Properties -> Static website hosting -> Check if 'S3 static website hosting' parameter has 'Enabled' value.

## Step 3 — Make the bucket publicly readable (intentional shortcut)

For a website endpoint to work simply, we’ll allow public reads.
This is a **lab shortcut** (call it out in your article).

Disable “Block Public Access” for this bucket:

```bash
aws s3api put-public-access-block   --bucket "$BUCKET_NAME"   --public-access-block-configuration '{
    "BlockPublicAcls": false,
    "IgnorePublicAcls": false,
    "BlockPublicPolicy": false,
    "RestrictPublicBuckets": false
  }'
```

Apply a bucket policy for public read of objects:

```bash
cat > /tmp/s3-public-read-policy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
    }
  ]
}
JSON

aws s3api put-bucket-policy   --bucket "$BUCKET_NAME"   --policy file:///tmp/s3-public-read-policy.json
```

Expected result:
- Bucket policy is attached.

You should find the new policy at AWS -> S3 -> Buckets -> BUCKET_NAME -> Permissions -> Bucket policy

## Step 4 — Create an IAM user for CI (static keys)

Create an IAM user:

```bash
aws iam create-user --user-name "gh-actions-s3-deploy-user"
```

Attach an inline policy scoped to this bucket (upload + list):

```bash
cat > /tmp/iam-user-s3-policy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::$BUCKET_NAME"
    },
    {
      "Sid": "WriteObjects",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:DeleteObject", "s3:PutObjectAcl"],
      "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
    }
  ]
}
JSON

aws iam put-user-policy   --user-name "gh-actions-s3-deploy-user"   --policy-name "S3DeployToSingleBucket"   --policy-document file:///tmp/iam-user-s3-policy.json
```

Create an access key:

```bash
aws iam create-access-key --user-name "gh-actions-s3-deploy-user" > /tmp/gh-actions-access-key.json
cat /tmp/gh-actions-access-key.json | jq
```

Expected result:
- You have `AccessKeyId` and `SecretAccessKey` in `/tmp/gh-actions-access-key.json`.

## Step 5 — Add GitHub Secrets

In your GitHub repository settings → **Secrets and variables** → **Actions** add:

- `AWS_ACCESS_KEY_ID` = from `/tmp/gh-actions-access-key.json`
- `AWS_SECRET_ACCESS_KEY` = from `/tmp/gh-actions-access-key.json`
- `AWS_REGION` = `<AWS_REGION>`
- `S3_BUCKET` = `<BUCKET_NAME>`

Expected result:
- Secrets are present in the repo.

## Step 6 — Add Phase 1 workflow

Create `.github/workflows/gh-aws-oidc-deploy-phase1.yml`:

```yaml
name: Deploy to S3 (Phase 1 - static keys)

on:
  workflow_dispatch: # manual trigger from GitHub UI
  push:
    branches: [ "main" ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials (static keys)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Who am I?
        run: aws sts get-caller-identity

      - name: Deploy site to S3
        run: |
          aws s3 sync ./examples/site "s3://${{ secrets.S3_BUCKET }}/" --delete
```

Commit and push to `main` or run manually.

Expected result:
- GitHub Actions job succeeds.

## Step 7 — Validate Phase 1

List bucket content:

```bash
aws s3 ls "s3://$BUCKET_NAME/"
```

Expected result:
- You see `index.html`.

Verify website endpoint:

```bash
echo "http://$BUCKET_NAME.s3-website-$AWS_REGION.amazonaws.com"
curl -s "http://$BUCKET_NAME.s3-website-$AWS_REGION.amazonaws.com" | head
```

Expected result:
- HTML content returned.

---

# Phase 2 — Reduce trust / Harden access

Goal: keep the same deploy, but remove long‑lived AWS keys from GitHub and use OIDC → role assumption.

## Step 1 — Create the GitHub OIDC provider in AWS IAM

Create an OIDC provider for GitHub Actions:

```bash
aws iam create-open-id-connect-provider   --url "https://token.actions.githubusercontent.com"   --client-id-list "sts.amazonaws.com"   --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
```
> "6938fd4d98bab03faadb97b34396831e3780aea1" is a cryptographic fingerprint of GitHub's SSL certificate. It's predefined and published by GitHub. AWS uses this to verify that tokens actually came from GitHub's authentic server and haven't been forged. It's like checking an ID before trusting someone's credentials.

Expected result:
- Command returns an ARN similar to:
  `arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com`

Store the OIDC provider ARN:

```bash
export OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
echo "$OIDC_PROVIDER_ARN"
```

## Step 2 — Create an IAM role with a repo-scoped trust policy

Create trust policy scoped to your repo and branch:

```bash
cat > /tmp/trust-policy-github-oidc.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "$OIDC_PROVIDER_ARN"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_OWNER}/${GITHUB_REPO}:ref:refs/heads/main"
        }
      }
    }
  ]
}
JSON
```

Create the role:

```bash
aws iam create-role   --role-name "$ROLE_NAME"   --assume-role-policy-document file:///tmp/trust-policy-github-oidc.json
```

Expected result:
- Role exists.

## Step 3 — Attach least-privilege S3 permissions to the role

Create a policy document for the role:

```bash
cat > /tmp/role-s3-policy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::$BUCKET_NAME"
    },
    {
      "Sid": "WriteObjects",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
    }
  ]
}
JSON
```

Attach it as an inline role policy:

```bash
aws iam put-role-policy   --role-name "$ROLE_NAME"   --policy-name "S3DeployToSingleBucket"   --policy-document file:///tmp/role-s3-policy.json
```

Expected result:
- Role has the required S3 permissions.

## Step 4 — Update workflow to use OIDC (no AWS keys)

Create `.github/workflows/deploy-phase2-oidc.yml`:

```yaml
name: Deploy to S3 (Phase 2 - OIDC)

on:
  push:
    branches: [ "main" ]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/GitHubActionsS3DeployRole
          aws-region: ${{ secrets.AWS_REGION }}
          role-session-name: gha-oidc-s3-deploy

      - name: Who am I?
        run: aws sts get-caller-identity

      - name: Deploy site to S3
        run: |
          aws s3 sync ./examples/site "s3://${{ secrets.S3_BUCKET }}/" --delete
```

Update repo secrets:
- Add `AWS_ACCOUNT_ID` = `<AWS_ACCOUNT_ID>`
- Ensure `AWS_REGION` and `S3_BUCKET` still exist
- In the workflow, replace `GitHubActionsS3DeployRole` if you used a different `<ROLE_NAME>`

Then **delete** these secrets from the repo:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

Expected result:
- Repo has no long‑lived AWS keys stored.

## Step 5 — Validate Phase 2

- Push a commit to `main`.
- The workflow should succeed.
- In job logs:
  - `aws sts get-caller-identity` should show an **assumed role** identity.

Validate S3 content is still updated:

```bash
aws s3 ls "s3://$BUCKET_NAME/"
```

Optional (recommended): validate CloudTrail events
- CloudTrail → Event history
- Filter event source: `sts.amazonaws.com`
- Look for `AssumeRoleWithWebIdentity`

Expected result:
- CloudTrail shows role assumption by GitHub Actions.

---

## Validation checklist

- [ ] Phase 1 workflow deploys to S3 successfully.
- [ ] Phase 2 workflow deploys to S3 successfully **without** `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` in GitHub.
- [ ] IAM trust policy is scoped to `repo:<GITHUB_OWNER>/<GITHUB_REPO>:ref:refs/heads/main`.
- [ ] `aws sts get-caller-identity` shows assumed role during Phase 2.
- [ ] CloudTrail shows `AssumeRoleWithWebIdentity` events.

---

## Troubleshooting

### Symptom: `No OpenIDConnect provider found`
**Likely cause:** OIDC provider not created, wrong account, or wrong URL.
**Fix:** confirm provider exists:

```bash
aws iam list-open-id-connect-providers
aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN"
```

### Symptom: `AccessDenied` on `sts:AssumeRoleWithWebIdentity`
**Likely cause:** trust policy `sub` doesn’t match your repo/branch or you forgot `permissions: id-token: write`.
**Fix:**
- ensure the workflow has `permissions: id-token: write`
- confirm trust policy matches: `repo:<OWNER>/<REPO>:ref:refs/heads/main`

### Symptom: `AccessDenied` on `s3:PutObject` / `s3:ListBucket`
**Likely cause:** bucket ARN or object ARN mismatch, wrong bucket name, or policy too strict.
**Fix:**

```bash
aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "S3DeployToSingleBucket"
aws s3api get-bucket-policy --bucket "$BUCKET_NAME"
```

### Symptom: Website URL returns `403 Forbidden`
**Likely cause:** Block Public Access still enabled or bucket policy missing.
**Fix:**

```bash
aws s3api get-public-access-block --bucket "$BUCKET_NAME"
aws s3api get-bucket-policy --bucket "$BUCKET_NAME"
```

---

## Cleanup

**S3**
```bash
aws s3 rm "s3://$BUCKET_NAME" --recursive
aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
```

**IAM user (Phase 1)**
```bash
aws iam list-access-keys --user-name "gh-actions-s3-deploy-user"
# delete the access key id(s) you created
aws iam delete-access-key --user-name "gh-actions-s3-deploy-user" --access-key-id "<ACCESS_KEY_ID>"

aws iam delete-user-policy --user-name "gh-actions-s3-deploy-user" --policy-name "S3DeployToSingleBucket"
aws iam delete-user --user-name "gh-actions-s3-deploy-user"
```

**IAM role + OIDC provider (Phase 2)**
```bash
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "S3DeployToSingleBucket"
aws iam delete-role --role-name "$ROLE_NAME"
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN"
```
