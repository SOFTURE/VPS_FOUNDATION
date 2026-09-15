#!/usr/bin/env bash
#
# One-off VPS bootstrap (hardening + Docker) without creating inventory files —
# everything is passed through --extra-vars.
#
# Useful when you only need to prepare a fresh server, with the infrastructure
# (services) deployed separately or from another repository.
#
# Requirements:
#   - collection installed locally:  ansible-galaxy collection install . --force
#   - a public key that ALREADY works on the server (password login is not
#     supported — Ansible would need sshpass)
#
# Example:
#   ./scripts/bootstrap.sh \
#     --host 203.0.113.10 \
#     --user deploy \
#     --pubkey ~/.ssh/id_ed25519.pub
#
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"

# --- defaults ----------------------------------------------------------------
host=""
appUser=""
pubKey=""
sshUser="ubuntu"
sshPort="22"
timezone="Europe/Warsaw"
locale="en_US.UTF-8"
githubActions="false"
checkMode="false"
extraArgs=()

usage() {
  cat <<USAGE
$SCRIPT_NAME - one-off VPS bootstrap (hardening + Docker)

REQUIRED:
  --host <ip>             Server IP address
  --user <name>           Application user to create (vps_app_user)
  --pubkey <path>         SSH public key for that user

OPTIONAL:
  --ssh-user <name>       User to connect as (default: $sshUser)
  --ssh-port <port>       SSH port (default: $sshPort)
  --timezone <zone>       System timezone (default: $timezone)
  --locale <locale>       System locale (default: $locale)
  --github-actions        Prompt for an extra GitHub Actions public key
  --check                 Dry run (--check --diff)
  -h, --help              This help

Arguments after '--' are forwarded to ansible-playbook, e.g:
  $SCRIPT_NAME --host 203.0.113.10 --user deploy --pubkey ~/.ssh/id_ed25519.pub -- --tags docker

NOTE: --check does not run to completion. In a dry run authorized_keys is never
actually written, so the lockout guard in the system_hardening role aborts the
play. That is a check-mode limitation, not a broken configuration — the dry run
is only useful for verifying connectivity and variables.
USAGE
}

fail() { echo "ERROR: $*" >&2; exit 1; }

# --- argument parsing --------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)           host="${2:-}"; shift 2 ;;
    --user)           appUser="${2:-}"; shift 2 ;;
    --pubkey)         pubKey="${2:-}"; shift 2 ;;
    --ssh-user)       sshUser="${2:-}"; shift 2 ;;
    --ssh-port)       sshPort="${2:-}"; shift 2 ;;
    --timezone)       timezone="${2:-}"; shift 2 ;;
    --locale)         locale="${2:-}"; shift 2 ;;
    --github-actions) githubActions="true"; shift ;;
    --check)          checkMode="true"; shift ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; extraArgs=("$@"); break ;;
    *)                fail "unknown argument: $1 (see --help)" ;;
  esac
done

[[ -n "$host" ]]    || { usage >&2; fail "--host is required"; }
[[ -n "$appUser" ]] || { usage >&2; fail "--user is required"; }
[[ -n "$pubKey" ]]  || { usage >&2; fail "--pubkey is required"; }

# expand ~ in the key path
pubKey="${pubKey/#\~/$HOME}"
[[ -f "$pubKey" ]] || fail "public key file does not exist: $pubKey"

pubKeyContent=$(< "$pubKey")
[[ "$pubKeyContent" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp[0-9]+)[[:space:]] ]] \
  || fail "this does not look like an SSH public key: $pubKey"

command -v ansible-playbook >/dev/null 2>&1 || fail "ansible-playbook not found in PATH"

# --- 1Password agent (when available) ----------------------------------------
# Private keys kept in 1Password never touch the disk — ssh has to pull them
# from the agent, and IdentityFile then points at the .pub file.
opAgentSock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
if [[ -S "$opAgentSock" && -z "${SSH_AUTH_SOCK:-}" ]]; then
  export SSH_AUTH_SOCK="$opAgentSock"
fi

# --- verify key-based access -------------------------------------------------
echo "==> Checking SSH access to ${sshUser}@${host}:${sshPort}"
if ! ssh -o BatchMode=yes \
         -o ConnectTimeout=10 \
         -o StrictHostKeyChecking=accept-new \
         -o IdentitiesOnly=yes \
         -i "$pubKey" \
         -p "$sshPort" \
         "${sshUser}@${host}" true 2>/dev/null; then
  fail "key-based login does not work.
      Install the key on the server before running the bootstrap:
        ssh-copy-id -i $pubKey ${sshUser}@${host}
      (Ansible cannot log in with a password without sshpass, which Homebrew no longer ships.)"
fi
echo "    OK - key works"

# --- build the command -------------------------------------------------------
# Variables are passed as JSON rather than 'key=value'. Why:
#   - an SSH public key contains spaces, and in 'key=value' form Ansible keeps
#     only the first token (the role would receive a bare "ssh-rsa"),
#   - the value '-o IdentitiesOnly=yes' in 'key=value' form is parsed by
#     argparse and '-o' ends up read as a flag of ansible-playbook itself
#     ("argument -o: expected one argument" -> WORKER HARD EXIT).
# JSON sidesteps both.
extraVarsJson=$(
  pubKeyContent="$pubKeyContent" \
  host="$host" sshUser="$sshUser" sshPort="$sshPort" pubKey="$pubKey" \
  appUser="$appUser" timezone="$timezone" locale="$locale" \
  githubActions="$githubActions" \
  python3 -c '
import json, os
print(json.dumps({
    # ansible_host must be explicit: the playbook runs ssh-keyscan
    # {{ ansible_host }} with delegate_to: localhost, and with an inline
    # inventory the variable is unset, so the keyscan would hit localhost.
    "ansible_host": os.environ["host"],
    "ansible_user": os.environ["sshUser"],
    "ansible_port": os.environ["sshPort"],
    "ansible_ssh_private_key_file": os.environ["pubKey"],
    "ansible_ssh_common_args": "-o IdentitiesOnly=yes",
    "vps_app_user": os.environ["appUser"],
    "vps_app_group": os.environ["appUser"],
    "vps_timezone": os.environ["timezone"],
    "vps_locale": os.environ["locale"],
    "vps_prompt_for_ssh_key": False,
    "vps_github_actions_ssh_required": os.environ["githubActions"] == "true",
    "vps_app_user_ssh_public_key_local": os.environ["pubKeyContent"].strip(),
}))
'
)

playbookArgs=(
  softure.vps_foundation.vps_bootstrap
  -i "${host},"
  -e "$extraVarsJson"
)

[[ "$checkMode" == "true" ]] && playbookArgs+=(--check --diff)
[[ ${#extraArgs[@]} -gt 0 ]] && playbookArgs+=("${extraArgs[@]}")

echo "==> Bootstrapping ${host} (target user: ${appUser})"
ansible-playbook "${playbookArgs[@]}"

echo
echo "==> Done. Log in as '${appUser}' from now on:"
echo "    ssh -i ${pubKey} ${appUser}@${host}"
