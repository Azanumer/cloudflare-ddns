# Cloudflare Dynamic DNS

Keep a Cloudflare DNS record in sync with a changing home-server IP. IPv4 and/or IPv6, token-scoped, with a systemd timer — no third-party DDNS client needed.

## What's inside

| File | What it does |
|---|---|
| `update-dns.sh` | Updates A/AAAA records via the Cloudflare API; skips the API call when the IP hasn't changed |
| `cfddns.service` / `cfddns.timer` | systemd units to run the updater every 5 minutes |

## Setup

1. Create an API token at [dash.cloudflare.com](https://dash.cloudflare.com) → **Manage Account → API Tokens** with **Zone → DNS → Edit** on your zone.
2. Create `/etc/cfddns.conf`:

   ```
   CF_API_TOKEN=your_token_here
   ZONE=example.com
   HOSTS="home router"   # "@" = apex (example.com itself)
   V4=yes
   V6=no
   ```

3. Install and enable the timer:

   ```bash
   sudo cp update-dns.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/update-dns.sh
   sudo cp cfddns.service cfddns.timer /etc/systemd/system/
   sudo systemctl daemon-reload && sudo systemctl enable --now cfddns.timer
   ```

   Or run it from cron every 5 minutes:

   ```bash
   */5 * * * * /usr/local/bin/update-dns.sh --config /etc/cfddns.conf >> /var/log/cfddns.log 2>&1
   ```

Records are created as DNS-only (`proxied: false`) with a 300s TTL.

MIT licensed. Contributions welcome.
