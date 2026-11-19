"""Sondagem: quais dados abertos de pedágio (ANTT) e municípios (IBGE) existem e em que formato."""
import csv, io, json, urllib.request

def get(url, limit=None):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read(limit) if limit else r.read()

def peek(url):
    try:
        raw = get(url, 400_000)
        text = None
        for enc in ("utf-8-sig", "latin-1"):
            try:
                text = raw.decode(enc); break
            except Exception:
                continue
        sep = ";" if text.count(";") > text.count(",") else ","
        rows = list(csv.reader(io.StringIO(text), delimiter=sep))
        print("  COLUNAS:", rows[0])
        for row in rows[1:6]:
            print("  ", row)
        print("  linhas na amostra:", len(rows) - 1)
    except Exception as e:
        print("  erro ao ler", e)

seen = set()
for q in ["pedagio", "praca", "tarifa"]:
    print(f"\n=== ANTT busca: {q} ===")
    try:
        d = json.loads(get(f"https://dados.antt.gov.br/api/3/action/package_search?q={q}&rows=50"))
    except Exception as e:
        print("erro", e); continue
    for p in d["result"]["results"]:
        print("PKG", p["name"], "|", p["title"])
        for r in p["resources"]:
            url = r.get("url") or ""
            print("   RES", r.get("format"), "|", r.get("name"), "|", url)
            text = (p["name"] + " " + (r.get("name") or "")).lower()
            if url not in seen and (r.get("format") or "").upper() == "CSV" and any(k in text for k in ("pedagio", "praca", "tarifa")) and len(seen) < 15:
                seen.add(url)
                peek(url)

print("\n=== IBGE municípios ===")
try:
    m = json.loads(get("https://servicodados.ibge.gov.br/api/v1/localidades/municipios"))
    print("total:", len(m))
    print(json.dumps(m[0], ensure_ascii=False)[:700])
except Exception as e:
    print("erro IBGE", e)

print("\n=== Coordenadas de municípios (kelvins/municipios-brasileiros) ===")
peek("https://raw.githubusercontent.com/kelvins/municipios-brasileiros/main/csv/municipios.csv")
