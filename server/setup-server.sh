#!/usr/bin/env bash
# One-command setup for the HeyCode AI server on an Oracle Ubuntu 24.04 VM.
# Installs Hermes Agent, connects it to full GLM-5.3 through OpenRouter,
# turns on Hermes' private API, and serves it over https with Caddy.
#
# Run on the server as the "ubuntu" user:
#   curl -fsSL <raw url of this file> -o setup-server.sh && bash setup-server.sh
set -euo pipefail

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
  echo "Please run this as the normal 'ubuntu' user, not root." >&2
  exit 1
fi

# --- 1. Questions up front, so the rest can run unattended -------------------
say "Your OpenRouter API key (starts with sk-or-). It won't be shown as you type."
read -rsp "OpenRouter key: " OPENROUTER_KEY; echo
case "$OPENROUTER_KEY" in sk-or-*) ;; *) echo "That doesn't look like an OpenRouter key." >&2; exit 1 ;; esac

PUBLIC_IP=$(curl -fsS https://api.ipify.org)
DOMAIN="${PUBLIC_IP//./-}.sslip.io"
API_KEY=$(openssl rand -hex 24)

# --- 2. System packages and firewall -----------------------------------------
say "Updating the server (a few minutes)"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq upgrade
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq install curl git openssl \
  debian-keyring debian-archive-keyring apt-transport-https netfilter-persistent

say "Opening web ports 80 and 443 in the server's own firewall"
for port in 80 443; do
  sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null \
    || sudo iptables -I INPUT 5 -p tcp --dport "$port" -j ACCEPT
done
sudo netfilter-persistent save >/dev/null

# --- 3. Hermes Agent ----------------------------------------------------------
say "Installing Hermes Agent"
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive --skip-computer-use
export PATH="$HOME/.local/bin:$PATH"
grep -q '.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

say "Connecting Hermes to GLM-5.3 through OpenRouter"
# Secrets and API settings live in ~/.hermes/.env
set_env() {
  mkdir -p "$HOME/.hermes"; touch "$HOME/.hermes/.env"; chmod 600 "$HOME/.hermes/.env"
  sed -i "/^$1=/d" "$HOME/.hermes/.env"
  printf '%s=%s\n' "$1" "$2" >> "$HOME/.hermes/.env"
}
set_env OPENROUTER_API_KEY "$OPENROUTER_KEY"
hermes config set model z-ai/glm-5.3

# The app talks to Hermes through its OpenAI-style API, kept on localhost
# and published to the internet only through Caddy's https.
set_env API_SERVER_ENABLED true
set_env API_SERVER_KEY "$API_KEY"
set_env API_SERVER_HOST 127.0.0.1
set_env API_SERVER_PORT 8642

say "Choose the model: pick OpenRouter, then z-ai/glm-5.3"
hermes model

# --- 4. Keep Hermes running ---------------------------------------------------
say "Running Hermes as an always-on service"
sudo tee /etc/systemd/system/hermes.service >/dev/null <<UNIT
[Unit]
Description=Hermes Agent gateway and API
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME
Environment=PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$HOME/.local/bin/hermes gateway
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now hermes

# --- 5. Caddy for https -------------------------------------------------------
say "Installing Caddy for a secure https address"
curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | sudo gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq install caddy

sudo tee /etc/caddy/Caddyfile >/dev/null <<CADDY
$DOMAIN {
	reverse_proxy 127.0.0.1:8642
}
CADDY
sudo systemctl restart caddy

# --- 6. Check and hand over ---------------------------------------------------
say "Checking that everything answers"
for i in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:8642/health" >/dev/null 2>&1; then break; fi
  sleep 2
done
if curl -fsS "http://127.0.0.1:8642/health" >/dev/null 2>&1; then
  echo "Hermes API: OK"
else
  echo "Hermes API is not answering yet. Check with: sudo journalctl -u hermes -n 50"
fi

cat > "$HOME/heycode-app-settings.txt" <<INFO
Server address: https://$DOMAIN/v1
Private key:    $API_KEY
INFO
chmod 600 "$HOME/heycode-app-settings.txt"

say "Done! Put these two values into the HeyCode app's settings:"
cat "$HOME/heycode-app-settings.txt"
echo
echo "They are also saved in ~/heycode-app-settings.txt on this server."
echo "Keep the private key secret: anyone with it can use your AI."
