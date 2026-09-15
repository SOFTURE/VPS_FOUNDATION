#!/usr/bin/env bash
#
# Jednorazowy bootstrap serwera VPS (hardening + Docker) bez tworzenia
# plikow inventory - wszystko przekazywane przez --extra-vars.
#
# Uzyteczne gdy chcesz tylko przygotowac swiezy serwer, a infrastruktura
# (uslugi) bedzie deployowana osobno albo z innego repozytorium.
#
# Wymagania:
#   - kolekcja zainstalowana lokalnie:  ansible-galaxy collection install . --force
#   - klucz publiczny, ktory JUZ dziala na serwerze (dostep na haslo nie jest
#     obslugiwany - Ansible wymagaloby sshpass)
#
# Przyklad:
#   ./scripts/bootstrap.sh \
#     --host 203.0.113.10 \
#     --user deploy \
#     --pubkey ~/.ssh/id_ed25519.pub
#
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"

# --- wartosci domyslne -------------------------------------------------------
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
$SCRIPT_NAME - jednorazowy bootstrap VPS (hardening + Docker)

WYMAGANE:
  --host <ip>             Adres IP serwera
  --user <nazwa>          Uzytkownik aplikacyjny do utworzenia (vps_app_user)
  --pubkey <sciezka>      Klucz publiczny SSH dla tego uzytkownika

OPCJONALNE:
  --ssh-user <nazwa>      Uzytkownik do polaczenia (domyslnie: $sshUser)
  --ssh-port <port>       Port SSH (domyslnie: $sshPort)
  --timezone <strefa>     Strefa czasowa (domyslnie: $timezone)
  --locale <locale>       Locale systemu (domyslnie: $locale)
  --github-actions        Pytaj o dodatkowy klucz publiczny dla GitHub Actions
  --check                 Dry-run (--check --diff)
  -h, --help              Ta pomoc

Argumenty po '--' trafiaja bezposrednio do ansible-playbook, np:
  $SCRIPT_NAME --host 203.0.113.10 --user deploy --pubkey ~/.ssh/id_ed25519.pub -- --tags docker

UWAGA: --check nie przechodzi do konca. W dry-run plik authorized_keys nie
jest realnie zapisywany, wiec zabezpieczenie przed lockoutem w roli
system_hardening przerywa przebieg. To ograniczenie check mode, nie bledna
konfiguracja - dry-run sluzy tylko do sprawdzenia polaczenia i zmiennych.
USAGE
}

fail() { echo "BLAD: $*" >&2; exit 1; }

# --- parsowanie argumentow ---------------------------------------------------
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
    *)                fail "nieznany argument: $1 (uzyj --help)" ;;
  esac
done

[[ -n "$host" ]]    || { usage >&2; fail "--host jest wymagany"; }
[[ -n "$appUser" ]] || { usage >&2; fail "--user jest wymagany"; }
[[ -n "$pubKey" ]]  || { usage >&2; fail "--pubkey jest wymagany"; }

# rozwiniecie ~ w sciezce klucza
pubKey="${pubKey/#\~/$HOME}"
[[ -f "$pubKey" ]] || fail "plik klucza publicznego nie istnieje: $pubKey"

pubKeyContent=$(< "$pubKey")
[[ "$pubKeyContent" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp[0-9]+)[[:space:]] ]] \
  || fail "to nie wyglada na klucz publiczny SSH: $pubKey"

command -v ansible-playbook >/dev/null 2>&1 || fail "brak ansible-playbook w PATH"

# --- agent 1Password (jesli dostepny) ----------------------------------------
# Klucze prywatne trzymane w 1Password nie istnieja na dysku - ssh musi
# pobrac je z agenta, a IdentityFile wskazuje wtedy na plik .pub.
opAgentSock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
if [[ -S "$opAgentSock" && -z "${SSH_AUTH_SOCK:-}" ]]; then
  export SSH_AUTH_SOCK="$opAgentSock"
fi

# --- sprawdzenie dostepu po kluczu -------------------------------------------
echo "==> Sprawdzam dostep SSH do ${sshUser}@${host}:${sshPort}"
if ! ssh -o BatchMode=yes \
         -o ConnectTimeout=10 \
         -o StrictHostKeyChecking=accept-new \
         -o IdentitiesOnly=yes \
         -i "$pubKey" \
         -p "$sshPort" \
         "${sshUser}@${host}" true 2>/dev/null; then
  fail "logowanie kluczem nie dziala.
      Wgraj klucz na serwer zanim odpalisz bootstrap:
        ssh-copy-id -i $pubKey ${sshUser}@${host}
      (Ansible nie loguje sie haslem bez sshpass, ktorego Homebrew nie dystrybuuje.)"
fi
echo "    OK - klucz dziala"

# --- budowa komendy ----------------------------------------------------------
# Zmienne przekazujemy jako JSON, nie jako 'klucz=wartosc'. Powod:
#   - klucz publiczny SSH zawiera spacje, a w formie 'klucz=wartosc' Ansible
#     bierze tylko pierwszy token (do roli trafialoby samo "ssh-rsa"),
#   - wartosc '-o IdentitiesOnly=yes' w formie 'klucz=wartosc' jest parsowana
#     przez argparse i '-o' laduje jako flaga samego ansible-playbook
#     ("argument -o: expected one argument" -> WORKER HARD EXIT).
# JSON omija oba problemy.
extraVarsJson=$(
  pubKeyContent="$pubKeyContent" \
  host="$host" sshUser="$sshUser" sshPort="$sshPort" pubKey="$pubKey" \
  appUser="$appUser" timezone="$timezone" locale="$locale" \
  githubActions="$githubActions" \
  python3 -c '
import json, os
print(json.dumps({
    # ansible_host musi byc jawny: playbook robi ssh-keyscan {{ ansible_host }}
    # z delegate_to: localhost, a przy inline inventory zmienna nie jest
    # ustawiona i keyscan trafilby na localhost.
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

echo "==> Bootstrap ${host} (uzytkownik docelowy: ${appUser})"
ansible-playbook "${playbookArgs[@]}"

echo
echo "==> Gotowe. Loguj sie teraz jako '${appUser}':"
echo "    ssh -i ${pubKey} ${appUser}@${host}"
