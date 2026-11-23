"""Percentis de latência no lado do servidor, a partir dos access logs. Uso: python3 scripts/server_latency.py [minutos=30]"""
import json, subprocess, sys, time

minutes = int(sys.argv[1]) if len(sys.argv) > 1 else 30
start = int((time.time() - minutes * 60) * 1000)

def pct(v, p):
    v = sorted(v); return v[max(0, min(len(v) - 1, round(p / 100 * len(v)) - 1))] if v else None

for name in ("open", "protected"):
    out = subprocess.run(["aws", "logs", "filter-log-events", "--profile", "dev",
                          "--log-group-name", f"/aws/apigateway/api-demo-{name}",
                          "--start-time", str(start), "--output", "json"],
                         capture_output=True, text=True, check=True)
    rows = [json.loads(e["message"]) for e in json.loads(out.stdout)["events"]]
    ok = [r for r in rows if r["status"] == "200" and r["integrationLatency"] not in ("-", "")]
    resp = [int(r["responseLatency"]) for r in ok]
    integ = [int(r["integrationLatency"]) for r in ok]
    over = [a - b for a, b in zip(resp, integ)]
    waf = [int(r["wafLatency"]) for r in ok if r["wafLatency"] not in ("-", "")]
    auth = [int(r["authorizeLatency"]) for r in ok if r["authorizeLatency"] not in ("-", "")]
    print(f"== {name}: {len(ok)} req 200 (de {len(rows)} total)")
    print(f"   response   p50={pct(resp,50)} p95={pct(resp,95)} ms")
    print(f"   lambda     p50={pct(integ,50)} p95={pct(integ,95)} ms")
    print(f"   overhead   p50={pct(over,50)} p95={pct(over,95)} ms  (response - lambda)")
    if waf:  print(f"   waf        p50={pct(waf,50)} p95={pct(waf,95)} ms")
    if auth: print(f"   authorize  p50={pct(auth,50)} p95={pct(auth,95)} ms")
