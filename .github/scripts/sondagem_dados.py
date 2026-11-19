"""Sondagem 2: praças do PR, receita por praça e tráfego equivalente (para estimar a tarifa)."""
import csv, io, json, urllib.request

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()

def rows(url):
    raw = get(url)
    for enc in ("utf-8-sig", "latin-1"):
        try:
            text = raw.decode(enc); break
        except Exception:
            continue
    sep = ";" if text[:2000].count(";") > text[:2000].count(",") else ","
    return list(csv.DictReader(io.StringIO(text), delimiter=sep))

base = "https://dados.antt.gov.br/dataset/"
pracas = rows(base + "a7e1e12d-f8e8-40cd-bc1f-57973a4a4a6d/resource/9aa29243-c54c-4084-bc3d-c44a75c9bd7e/download/dados-dos-praas-de-pedgio.csv")
print("praças total:", len(pracas), "ativas:", sum(1 for p in pracas if p.get("situacao", "").lower().startswith("ativ")))
print("por UF:", sorted({(p["uf"]) for p in pracas}))
for p in pracas:
    if p["uf"] == "PR":
        print("PR:", p["concessionaria"], "|", p["praca_de_pedagio"], "|", p["rodovia"], p["km_m"], "|", p["situacao"], "|", p["latitude"], p["longitude"])

print("\n=== Receita por praça 2025 ===")
rec = rows(base + "5213d6c6-f494-4cb6-93a7-822ee1cae157/resource/94127a8c-c3c2-497a-bec1-76d6376eebb4/download/receita_por_praca_2025.csv")
print("colunas:", list(rec[0].keys()))
for r in rec[:5]: print(r)
for r in rec:
    if "EPR" in r.get(list(rec[0].keys())[0], "").upper() or "PARAN" in json.dumps(r, ensure_ascii=False).upper():
        print("PR?", r); break

print("\n=== Tráfego equivalente 2026 mensal ===")
vol = rows(base + "f3ea994f-7435-4867-83b4-1ee5d1debbce/resource/a3e2858b-2f2a-4db7-9aa7-f18f766b1ac8/download/volume-trafego-equivalente-praca-pedagio-2026")
print("colunas:", list(vol[0].keys()))
for r in vol[:5]: print(r)
print("linhas:", len(vol))
