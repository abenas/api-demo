# api-demo: impacto de uma camada de proteção no API Gateway

POC que mede o custo e a eficácia de proteger um endpoint do Amazon API Gateway contra chamadas de clientes HTTP de terceiros (curl, Insomnia, Postman). Somente uma origem governada dentro da AWS pode chamar o endpoint protegido.

A POC provisiona com Terraform duas APIs REST que expõem a mesma Lambda de soma (`POST /sum`):

| API | Proteção |
|---|---|
| **protected** | AWS WAF, depois resource policy (apenas a role da Lambda `caller`, com `Deny` explícito para as demais identidades), depois autenticação `AWS_IAM` (SigV4) |
| **open** | apenas uma resource policy restrita ao IP de origem |

Os resultados (cenários de bloqueio, latência e caminhos de bypass) estão em [ANALISE.md](ANALISE.md). Em resumo, a proteção acrescenta **cerca de 7–8 ms** por requisição, dos quais uns 6 ms são do WAF.

## Pré-requisitos

- Terraform ≥ 1.6, AWS CLI v2, curl ≥ 7.75 e Python 3.
- Um profile AWS com permissão para criar recursos de API Gateway, Lambda, WAFv2 e CloudWatch Logs, e para criar roles do IAM com o prefixo `api-demo-` (inclusive `iam:PassRole` para os serviços Lambda e API Gateway).

## Uso

```bash
cp terraform.tfvars.example terraform.tfvars   # informe seu IP público
terraform init
terraform plan -out=tfplan
terraform apply tfplan

./scripts/test.sh                  # 5 cenários: qual camada bloqueia cada tipo de cliente
./scripts/bench.sh 100             # carga nos dois endpoints
python3 scripts/server_latency.py  # percentis do servidor, a partir dos access logs (aguarde 1-2 min)

terraform destroy
```

O profile padrão é `dev` e a região padrão é `sa-east-1`. Para usar outros valores, ajuste `aws_profile` e `aws_region` em `terraform.tfvars`.

Teste rápido do endpoint aberto:

```bash
curl -X POST "$(terraform output -raw open_url)" \
  -H "Content-Type: application/json" -d '{"a": 10, "b": 32}'
```

## Custo

O AWS WAF custa cerca de US$ 0,35 por dia enquanto estiver provisionado. Lambda, API Gateway e CloudWatch ficam perto de zero no volume da POC. Rode `terraform destroy` ao terminar.

> **Atenção:** o recurso `aws_api_gateway_account` define a role de logs do API Gateway para a **região inteira**. Em contas compartilhadas, verifique se já existe uma role configurada antes de aplicar.
