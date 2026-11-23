#!/usr/bin/env bash
# Compara latência: endpoint aberto (sua máquina) vs protegido (Lambda caller).
# Uso: ./scripts/bench.sh [N=50]
set -euo pipefail
cd "$(dirname "$0")/.."

N="${1:-50}"
PROFILE="${AWS_PROFILE:-dev}"
OPEN_URL=$(terraform output -raw open_url)
CALLER=$(terraform output -raw caller_function)

echo "== Aberto (cliente: sua máquina), $N requisições"
for _ in $(seq "$N"); do
  curl -s -o /dev/null -w "%{time_total}\n" -X POST "$OPEN_URL" \
    -H 'Content-Type: application/json' -d '{"a":2,"b":3}'
done | sort -n | awk '{a[NR]=$1*1000} END {i50=int(NR*0.5); if(i50<1)i50=1; i95=int(NR*0.95); if(i95<1)i95=1; printf "min=%.1fms p50=%.1fms p95=%.1fms max=%.1fms\n", a[1], a[i50], a[i95], a[NR]}'

echo "== Protegido (cliente: Lambda caller), $N requisições"
aws lambda invoke --profile "$PROFILE" --function-name "$CALLER" \
  --cli-binary-format raw-in-base64-out --payload "{\"iterations\": $N}" /tmp/.api-demo-bench >/dev/null
python3 -c 'import json,sys; d=json.load(open("/tmp/.api-demo-bench")); print("statuses=", d["statuses"], "latency_ms=", d["latency_ms"])'

cat <<MSG

Obs.: a latência do cliente inclui rede (sua casa -> sa-east-1 vs. dentro da AWS).
Para isolar o custo da camada de proteção: python3 scripts/server_latency.py
Ou compare manualmente:
  - CloudWatch > API Gateway: Latency vs IntegrationLatency das duas APIs
  - Access logs: campos wafLatency, authorizeLatency, responseLatency
    /aws/apigateway/api-demo-protected  e  /aws/apigateway/api-demo-open
MSG
