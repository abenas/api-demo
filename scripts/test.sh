#!/usr/bin/env bash
# Valida o comportamento de cada camada. Uso: ./scripts/test.sh
set -uo pipefail
cd "$(dirname "$0")/.."

PROFILE="${AWS_PROFILE:-dev}"
OPEN_URL=$(terraform output -raw open_url)
PROT_URL=$(terraform output -raw protected_url)
CALLER=$(terraform output -raw caller_function)
REGION=$(terraform output -raw region)
BODY='{"a": 2, "b": 3}'

run() {
  local title="$1"; shift
  echo -e "\n=== $title"
  curl -sS -o /tmp/.api-demo-body -w "HTTP %{http_code} (%{time_total}s)\n" "$@"
  head -c 300 /tmp/.api-demo-body; echo
}

run "1. Endpoint aberto, da sua máquina (esperado: 200)" \
  -X POST "$OPEN_URL" -H 'Content-Type: application/json' -d "$BODY"

run "2. Protegido com curl puro (esperado: 403 do WAF)" \
  -X POST "$PROT_URL" -H 'Content-Type: application/json' -d "$BODY"

run "3. Protegido, UA e Authorization falsificados p/ passar no WAF (esperado: 403 do IAM auth)" \
  -X POST "$PROT_URL" -A 'Mozilla/5.0' -H 'Content-Type: application/json' \
  -H 'Authorization: AWS4-HMAC-SHA256 Credential=FAKE/20260101/sa-east-1/execute-api/aws4_request, SignedHeaders=host, Signature=00' \
  -d "$BODY"

eval "$(aws configure export-credentials --profile "$PROFILE" --format env)"
run "4. Protegido, SigV4 válido com SUAS credenciais (esperado: 403 explicit deny da resource policy)" \
  -X POST "$PROT_URL" -A 'Mozilla/5.0' -H 'Content-Type: application/json' \
  --aws-sigv4 "aws:amz:${REGION}:execute-api" --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
  -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" -d "$BODY"

echo -e "\n=== 5. Via origem governada (Lambda caller) (esperado: 200)"
aws lambda invoke --profile "$PROFILE" --function-name "$CALLER" \
  --cli-binary-format raw-in-base64-out --payload '{"iterations": 1}' /tmp/.api-demo-caller >/dev/null \
  && cat /tmp/.api-demo-caller; echo
