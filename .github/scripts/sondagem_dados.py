"""Sondagem 3: estimar tarifa de carro por praça = receita / tráfego equivalente (mesmos meses)."""
import csv, io, urllib.request, collections

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                return r.read()
        except Exception as e:
            print("tentativa", attempt + 1, "falhou:", e)
    raise SystemExit("não baixou " + url)

def rows(url):
    raw = get(url)
    print("baixado", len(raw) // 1024, "KB", url.rsplit("/", 1)[-1])
    for enc in ("utf-8-sig", "latin-1"):
        try:
            text = raw.decode(enc); break
        except Exception:
            continue
    sep = ";" if text[:3000].count(";") > text[:3000].count(",") else ","
    return list(csv.DictReader(io.StringIO(text), delimiter=sep))

B = "https://dados.antt.gov.br/dataset/"
rec = rows(B + "5213d6c6-f494-4cb6-93a7-822ee1cae157/resource/94127a8c-c3c2-497a-bec1-76d6376eebb4/download/receita_por_praca_2025.csv")
print("receita colunas:", list(rec[0].keys())); [print(" ", r) for r in rec[:4]]
vol = rows(B + "f3ea994f-7435-4867-83b4-1ee5d1debbce/resource/a3e2858b-2f2a-4db7-9aa7-f18f766b1ac8/download/volume-trafego-equivalente-praca-pedagio-2026_mensal_consolidado.csv")
print("volume colunas:", list(vol[0].keys())); [print(" ", r) for r in vol[:4]]
print("concessionárias receita:", sorted({r.get(list(rec[0].keys())[0]) for r in rec})[:80])
