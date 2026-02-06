#!/usr/bin/env bash
set -euo pipefail

# ====== EDIT THIS ======
# GITLAB_FQDN="gitlab.example.com"
GITLAB_FQDN="gitlab.icovaliov.com"
# =======================

export DEBIAN_FRONTEND=noninteractive

echo "[*] Updating packages..."
apt-get update -y
apt-get install -y curl ca-certificates tzdata openssh-server perl gpg lsb-release ruby

echo "[*] Creating backups directory..."
mkdir -p /srv/gitlab-backups
chmod 700 /srv/gitlab-backups

# GitLab needs postfix or some MTA package; for a lab, install postfix in 'Local only' mode.
# This avoids install prompts if DEBIAN_FRONTEND is set, but some environments still ask.
echo "[*] Installing postfix (local only)..."
apt-get install -y postfix || true

# Install GitLab repo if not present
if ! command -v gitlab-ctl >/dev/null 2>&1; then
  echo "[*] Adding GitLab package repository..."
  curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash
fi

# Install GitLab CE if not installed
if ! dpkg -s gitlab-ce >/dev/null 2>&1; then
  echo "[*] Installing gitlab-ce..."
  apt-get install -y gitlab-ce
else
  echo "[*] gitlab-ce already installed, skipping package install."
fi

echo "[*] Configuring /etc/gitlab/gitlab.rb ..."
GITLAB_RB="/etc/gitlab/gitlab.rb"

# Ensure file exists
test -f "$GITLAB_RB"

# Set external_url
if grep -q "^external_url" "$GITLAB_RB"; then
  sed -i "s|^external_url .*|external_url \"https://${GITLAB_FQDN}\"|g" "$GITLAB_RB"
else
  echo "external_url \"https://${GITLAB_FQDN}\"" >> "$GITLAB_RB"
fi

# Disable bundled Nginx and run GitLab web on 8080 (so host Nginx can reverse proxy)
# NOTE: This is the simplest lab mode. Later you can run HTTPS internally too.
echo "[*] Applying gitlab.rb settings..."

cat >/tmp/gitlab_rb_patch.rb <<'RUBY'
f = ARGV[0]
txt = File.read(f)

def set_kv(txt, key, value)
  re = /^#{Regexp.escape(key)}\s*=.*$/
  if txt.match?(re)
    txt.gsub(re, "#{key} = #{value}")
  else
    txt + "\n#{key} = #{value}\n"
  end
end

txt = set_kv(txt, "nginx['enable']", "false")

# Puma (Rails app)
txt = set_kv(txt, "puma['listen']", "'0.0.0.0'")
txt = set_kv(txt, "puma['port']", "8080")

# GitLab Workhorse (should be the upstream for external Nginx)
# to make css/js load properly
txt = set_kv(txt, "gitlab_workhorse['listen_network']", "\"tcp\"")
txt = set_kv(txt, "gitlab_workhorse['listen_addr']", "\"0.0.0.0:8181\"")

# Backups
txt = set_kv(txt, "gitlab_rails['backup_path']", "\"/srv/gitlab-backups\"")

File.write(f, txt)
RUBY

ruby /tmp/gitlab_rb_patch.rb "$GITLAB_RB"
rm -f /tmp/gitlab_rb_patch.rb

echo "[*] Running gitlab-ctl reconfigure (can take a while)..."
gitlab-ctl reconfigure

echo "[*] Done."
echo "    GitLab should be listening on http://<VM-IP>:8080"
echo "    External URL set to: https://${GITLAB_FQDN}"

sudo systemctl status --no-pager gitlab-runsvdir