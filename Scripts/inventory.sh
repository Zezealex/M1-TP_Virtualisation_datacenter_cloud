#!/usr/bin/env bash
# NOVACORP PVE INVENTORY — TP01 EXPERT bonus
# Aucune valeur codée en dur : tout est lu dynamiquement sur le nœud.
set -u

FAIL=0

section() {
  printf '%s\n' "$1 :"
}

echo "===================================="
echo " NOVACORP PVE INVENTORY"
echo "===================================="
echo

# --- Identité ---
HOST="$(hostname 2>/dev/null)"
FQDN="$(hostname -f 2>/dev/null)"
section "Hostname"; echo "  $HOST"
section "FQDN"; echo "  ${FQDN:-inconnu}"
if [[ -z "$HOST" ]]; then FAIL=1; fi
if ! getent hosts "$FQDN" >/dev/null 2>&1; then
  echo "  [!] FQDN ne resout pas localement"
  FAIL=1
fi
echo

# --- Versions ---
section "PVE version"; echo "  $(pveversion 2>/dev/null | head -n1)"
if ! command -v pveversion >/dev/null 2>&1; then FAIL=1; fi
section "Kernel"; echo "  $(uname -r)"
echo

# --- CPU / RAM ---
CPU_MODEL="$(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^ +/,"",$2); print $2}')"
CPU_COUNT="$(nproc 2>/dev/null)"
section "CPU"; echo "  ${CPU_MODEL:-inconnu} (${CPU_COUNT:-?} vCPU)"
section "RAM"; echo "  $(free -h 2>/dev/null | awk '/^Mem:/ {print $2" total, "$3" utilisé"}')"
echo

# --- Réseau ---
DEFROUTE="$(ip route 2>/dev/null | grep '^default')"
section "Default route"; echo "  ${DEFROUTE:-aucune route par défaut}"
if [[ -z "$DEFROUTE" ]]; then FAIL=1; fi
section "Interfaces"
ip -br a 2>/dev/null | sed 's/^/  /'
echo

# --- Stockage ---
section "Storage"
if pvesm status >/dev/null 2>&1; then
  pvesm status 2>/dev/null | sed 's/^/  /'
else
  echo "  [!] pvesm status a échoué"
  FAIL=1
fi
echo

# --- Nested virtualization ---
VIRTCOUNT="$(grep -Ec '(vmx|svm)' /proc/cpuinfo 2>/dev/null || echo 0)"
KVM_LOADED="non"
if lsmod 2>/dev/null | grep -q '^kvm'; then KVM_LOADED="oui"; fi
section "Nested virtualization"
echo "  Flag CPU vmx/svm : ${VIRTCOUNT} ligne(s) matchée(s)"
echo "  Module KVM chargé : ${KVM_LOADED}"
if [[ "$VIRTCOUNT" -eq 0 || "$KVM_LOADED" == "non" ]]; then
  FAIL=1
fi
echo

# --- Services en échec ---
FAILED_UNITS="$(systemctl --failed --no-legend 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l)"
section "Failed services"
if [[ "$FAILED_UNITS" -eq 0 ]]; then
  echo "  Aucun"
else
  echo "  $FAILED_UNITS unité(s) en échec :"
  systemctl --failed --no-legend 2>/dev/null | sed 's/^/    /'
  FAIL=1
fi
echo

echo "===================================="
if [[ "$FAIL" -eq 0 ]]; then
  echo "STATUS: OK"
  exit 0
else
  echo "STATUS: CONTROLES ESSENTIELS EN ECHEC"
  exit 1
fi