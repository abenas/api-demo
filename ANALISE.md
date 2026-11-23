# Análise: camada de proteção no API Gateway

**Data:** 2026-11-23 · **Região:** sa-east-1

Esta análise mede o efeito de uma camada de proteção no Amazon API Gateway. O objetivo da camada é impedir que clientes HTTP de terceiros (curl, Insomnia, Postman e outros) chamem a API sem passar pelo autorizador governado.

## 1. Arquitetura testada

```
                     ┌──────────── API "protected" (REST, regional) ─────────────┐
Lambda "caller" ──►  │ WAF ─► Resource Policy (só role do caller) ─► Auth AWS_IAM│──► Lambda "sum"
(role autorizada,    └────────────────────────────────────────────────────────────┘        ▲
 assina SigV4)                                                                             │
                     ┌──────────── API "open" (REST, regional) ──────────────────┐         │
Máquina local ────►  │ Resource Policy: aws:SourceIp = <SEU_IP>/32               │─────────┘
                     └────────────────────────────────────────────────────────────┘
```

As duas APIs usam a **mesma Lambda `sum`**. Assim, a diferença medida vem apenas da camada de proteção.

| Endpoint | URL |
|---|---|
| Aberto | `https://<open-api-id>.execute-api.sa-east-1.amazonaws.com/v1/sum` |
| Protegido | `https://<protected-api-id>.execute-api.sa-east-1.amazonaws.com/v1/sum` |

### Camadas do endpoint protegido

1. **AWS WAF**, a primeira barreira, na borda:
   - limite de requisições por IP;
   - bloqueio dos User-Agents de clientes HTTP conhecidos;
   - bloqueio de requisições sem o header `Authorization: AWS4-HMAC-SHA256`;
   - regras gerenciadas `AWSManagedRulesCommonRuleSet` e `KnownBadInputs`.
2. **Autenticação IAM (SigV4):** o API Gateway recusa requisições sem assinatura válida.
3. **Resource policy:** dá `Allow` apenas para a role `api-demo-caller-lambda` e tem um `Deny` explícito para qualquer outro `aws:PrincipalArn`.

## 2. Resultado funcional

| # | Cliente | HTTP | Quem bloqueou |
|---|---|---|---|
| 1 | curl local → aberto | **200** `{"result": 5}` | — |
| 2 | curl puro → protegido | **403** `Forbidden` | WAF |
| 3 | curl com User-Agent e `Authorization` falsificados | **403** assinatura inválida | autenticação IAM (o WAF foi contornado) |
| 4 | curl com SigV4 **válido** (credenciais PowerUser) | **403** `explicit deny in a resource-based policy` | resource policy |
| 5 | Lambda `api-demo-caller` (origem governada) | **200** | — |

**Leitura do resultado:**
- **O WAF sozinho não basta.** Ele filtra por atributos que o cliente controla, como User-Agent e headers, e o cenário 3 conseguiu passar por ele. A função dele é descartar ruído e abuso antes do gateway.
- **A barreira de fato é a identidade.** A assinatura SigV4 junto com a resource policy recusou até uma credencial válida da conta (cenário 4).

## 3. Impacto na latência

Foram 100 requisições em cada endpoint. Os valores vêm dos access logs, medidos no servidor e sem a rede do cliente.

| Medida (ms) | Aberto | Protegido | Diferença |
|---|---|---|---|
| Resposta total, p50 / p95 | 19 / 26 | 26 / 33 | **+7 / +7** |
| Lambda (integração), p50 / p95 | 16 / 20 | 15 / 20 | ≈ 0 |
| Tempo do gateway (resposta − Lambda), p50 / p95 | 3 / 8 | 11 / 14 | **+8 / +6** |
| Inspeção do WAF, p50 / p95 | — | 6 / 7 | |

**Conclusão:** a camada de proteção custa **cerca de 7–8 ms por requisição**. Desse total, uns **6 ms são do WAF** e uns **2 ms vêm da validação SigV4 e da avaliação da resource policy**. Do lado do cliente, a Lambda caller também gasta tempo para assinar a requisição, mas esse custo é desprezível.

> Os números medidos no cliente (aberto p50 51 ms a partir da máquina local; protegido p50 32 ms de dentro da AWS) não servem para comparar o custo da proteção, porque a rede é diferente nos dois casos.

## 4. Adicionar `execute-api:Invoke` ao permission set libera o acesso local?

**Não. A requisição local continua bloqueada.**

Na avaliação de permissões da AWS, um **`Deny` explícito sempre vence qualquer `Allow`**. A resource policy da API protegida nega `execute-api:Invoke` a todo principal diferente da role `api-demo-caller-lambda`:

```json
{
  "Sid": "DenyEveryoneElse",
  "Effect": "Deny",
  "Principal": "*",
  "Action": "execute-api:Invoke",
  "Resource": "arn:aws:execute-api:sa-east-1:<ACCOUNT_ID>:<protected-api-id>/*",
  "Condition": {
    "StringNotEquals": { "aws:PrincipalArn": "arn:aws:iam::<ACCOUNT_ID>:role/api-demo-caller-lambda" }
  }
}
```

```
Requisição local assinada
  ├─ Permission set: Allow execute-api:Invoke                        ✅
  └─ Resource policy: Deny se aws:PrincipalArn ≠ role do caller     ❌  ← vence
```

O permission set `PowerUserAccess` **já concede** `execute-api:Invoke`, porque permite tudo exceto `iam:*`, `organizations:*` e `account:*`. O cenário 4 da seção 2 comprova isso: a requisição tinha assinatura válida e foi negada pelo `Deny` explícito. Adicionar a action, ou até `execute-api:*` para todos os recursos, não altera o resultado.

> Sem o `Deny` explícito, uma chamada da mesma conta seria autorizada só pela permissão de identidade, porque o `Allow` da identidade se soma ao `Allow` da resource policy. Por isso o `Deny` é indispensável.

## 5. Limites da proteção: caminhos de bypass

A proteção controla **quem chama**, não **com qual programa**. Um cliente qualquer que assine SigV4 com as credenciais da role autorizada (por exemplo, o `awscurl`) seria aceito. O bloqueio só se sustenta enquanto ninguém consegue **se passar pela role autorizada** ou **alterar a configuração**. No ambiente atual, o profile `dev` consegue fazer as duas coisas:

| Caminho de bypass | Permissão que habilita |
|---|---|
| Editar a trust policy de `api-demo-caller-lambda`, assumir a role e assinar localmente com as credenciais dela | `iam:UpdateAssumeRolePolicy` em `api-demo-*` (inline policy criada para o teste) |
| Alterar ou remover a resource policy, ou desassociar o WAF | `apigateway:*`, `wafv2:*` (PowerUser) |
| Alterar o código da Lambda caller, ou invocá-la com outro payload | `lambda:*` (PowerUser) |

### Recomendações para produção

- **SCP ou permissions boundary** negando `apigateway:Update*`, `apigateway:Delete*`, `wafv2:Disassociate*`, `wafv2:Update*`, `iam:UpdateAssumeRolePolicy` e `lambda:UpdateFunctionCode` nesses recursos, com exceção da role de deploy (pipeline de CI/CD).
- **Trust policy** da role autorizada restrita ao serviço de origem (`lambda.amazonaws.com`, como já está), sem permissão para usuários humanos alterarem essa trust policy.
- **Alarme** via CloudTrail e EventBridge para `UpdateRestApi`, `DisassociateWebACL`, `UpdateAssumeRolePolicy` e `UpdateFunctionCode`.
- **Isolamento de rede**, se for necessário: uma API privada atrás de um VPC endpoint, com `aws:SourceVpce` na resource policy, tira o endpoint da internet.

## 6. Reprodução e custo

```bash
terraform apply                       # provisiona
./scripts/test.sh                     # cenários funcionais da seção 2
./scripts/bench.sh 100                # carga nos dois endpoints
python3 scripts/server_latency.py     # percentis do servidor (aguarde 1-2 min pelos logs)
terraform destroy                     # remove tudo
```

- **Custo:** o WAF custa cerca de US$ 0,35 por dia enquanto estiver provisionado. Lambda, API Gateway e CloudWatch ficam perto de zero neste volume.
- **Antes do `destroy`:** a configuração `aws_api_gateway_account` é regional. Depois do destroy, o API Gateway da região pode continuar apontando para a role removida `api-demo-apigw-logs`.
