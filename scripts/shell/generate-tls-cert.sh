#!/usr/bin/env bash
#
# generate-tls-cert.sh
#
# Creates a self-signed TLS certificate valid for four years.
#
# Usage:
#   ./generate-tls-cert.sh <subjectName> [dns_san] [ip_san]
#
# Examples:
#   ./generate-tls-cert.sh web01
#   ./generate-tls-cert.sh web01.example.com web01.example.com
#   ./generate-tls-cert.sh web01.example.com web01.example.com 192.168.1.10
#   ./generate-tls-cert.sh web01 "" 192.168.1.10
#

set -euo pipefail

SUBJECT_NAME="${1:-}"
DNS_SAN="${2:-}"
IP_SAN="${3:-}"

KEY_FILE="tls.key"
CERT_FILE="tls.crt"
VALIDITY_DAYS=1461 # Four years, including one leap-day allowance

usage() {
  echo "Usage: $0 <subjectName> [dns_san] [ip_san]" >&2
  exit 1
}

if [[ -z "$SUBJECT_NAME" ]]; then
  usage
fi

if (( $# > 3 )); then
  usage
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl is not installed." >&2
  echo "Install it with: sudo dnf install -y openssl" >&2
  exit 1
fi

# Reject characters that could alter OpenSSL's subject or extension syntax.
if [[ "$SUBJECT_NAME" == *$'\n'* || "$SUBJECT_NAME" == *"/"* ]]; then
  echo "Error: subjectName must not contain '/' or newline characters." >&2
  exit 1
fi

for SAN_VALUE in "$DNS_SAN" "$IP_SAN"; do
  if [[ "$SAN_VALUE" == *$'\n'* || "$SAN_VALUE" == *","* ]]; then
    echo "Error: SAN values must not contain commas or newline characters." >&2
    exit 1
  fi
done

SAN_ITEMS=()

if [[ -n "$DNS_SAN" ]]; then
  SAN_ITEMS+=("DNS:${DNS_SAN}")
fi

if [[ -n "$IP_SAN" ]]; then
  SAN_ITEMS+=("IP:${IP_SAN}")
fi

OPENSSL_ARGS=(
  req
  -x509
  -newkey rsa:2048
  -nodes
  -sha256
  -days "$VALIDITY_DAYS"
  -keyout "$KEY_FILE"
  -out "$CERT_FILE"
  -subj "/CN=${SUBJECT_NAME}"
)

if (( ${#SAN_ITEMS[@]} > 0 )); then
  SAN_VALUE=$(IFS=,; printf '%s' "${SAN_ITEMS[*]}")
  OPENSSL_ARGS+=(-addext "subjectAltName=${SAN_VALUE}")
fi

openssl "${OPENSSL_ARGS[@]}"

chmod 600 "$KEY_FILE"

echo
echo "TLS certificate created successfully:"
echo "  Private key : ${KEY_FILE}"
echo "  Certificate : ${CERT_FILE}"
echo "  Validity    : ${VALIDITY_DAYS} days (4 years)"
echo

openssl x509 \
  -in "$CERT_FILE" \
  -noout \
  -subject \
  -issuer \
  -dates \
  -ext subjectAltName 2>/dev/null || true
