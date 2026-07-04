#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# First allow DNS and localhost before any restrictions
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# Allow inbound DNS responses
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow outbound SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# Allow inbound SSH responses
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Create ipset with CIDR support
ipset create allowed-domains hash:net

# ---------------------------------------------------------------------------
# GitHub IP ranges (optional). Lets git/gh reach GitHub over HTTPS.
# Set ALLOW_GITHUB=false (containerEnv) to skip this whole block.
# Resilient: a failed fetch warns and continues instead of aborting startup.
# ---------------------------------------------------------------------------
if [ "${ALLOW_GITHUB:-true}" = "true" ]; then
    echo "Fetching GitHub IP ranges..."
    gh_ranges=$(curl -s --connect-timeout 5 https://api.github.com/meta || true)
    if [ -z "$gh_ranges" ] || ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null 2>&1; then
        echo "WARNING: Failed to fetch usable GitHub IP ranges, skipping GitHub allowlist"
    else
        echo "Processing GitHub IPs..."
        while read -r cidr; do
            if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                echo "WARNING: Invalid CIDR range from GitHub meta: $cidr, skipping"
                continue
            fi
            echo "Adding GitHub range $cidr"
            ipset add --exist allowed-domains "$cidr"
        done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)
    fi
fi

# ---------------------------------------------------------------------------
# Domain allowlist. BASE_DOMAINS covers Claude Code + npm. Extend WITHOUT
# editing this file via either:
#   - the EXTRA_ALLOWED_DOMAINS env var (space/comma/newline separated), or
#   - a /workspace/.devcontainer/allowed-domains.txt file (one host per line).
# For other providers add e.g. api.openai.com, generativelanguage.googleapis.com.
# ---------------------------------------------------------------------------
BASE_DOMAINS=(
    "registry.npmjs.org"
    "api.anthropic.com"
    "sentry.io"
    "statsig.com"
)

EXTRA_FILE="/workspace/.devcontainer/allowed-domains.txt"
extra_from_file=""
if [ -f "$EXTRA_FILE" ]; then
    # Drop blank lines and # comments.
    extra_from_file=$(grep -vE '^[[:space:]]*(#|$)' "$EXTRA_FILE" || true)
fi

# Combine base + env + file, splitting on spaces, commas, tabs and newlines.
IFS=$' ,\n\t' read -r -a domain_list \
    <<< "${BASE_DOMAINS[*]} ${EXTRA_ALLOWED_DOMAINS:-} ${extra_from_file}" || true

for domain in "${domain_list[@]}"; do
    [ -z "$domain" ] && continue
    echo "Resolving $domain..."
    ips=""
    for attempt in 1 2 3; do
        ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
        if [ -n "$ips" ]; then
            break
        fi
        sleep 1
    done
    if [ -z "$ips" ]; then
        echo "WARNING: Failed to resolve $domain after 3 attempts, skipping"
        continue
    fi

    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "WARNING: Invalid IP from DNS for $domain: $ip, skipping"
            continue
        fi
        echo "Adding $ip for $domain"
        ipset add --exist allowed-domains "$ip"
    done < <(echo "$ips")
done

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# Set up remaining iptables rules
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Set default policies to DROP first
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# First allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Then allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"

# Fail-closed check: a NON-allowlisted host must be unreachable. Hard failure.
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# Positive check: Claude's API endpoint should be reachable. Warn (don't abort).
if curl --connect-timeout 5 -sI https://api.anthropic.com >/dev/null 2>&1; then
    echo "Firewall verification passed - able to reach https://api.anthropic.com as expected"
else
    echo "WARNING: unable to reach https://api.anthropic.com - check DNS/allowlist"
fi
