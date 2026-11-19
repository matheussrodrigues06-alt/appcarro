"""Gera dois arquivos para o app (dados abertos e gratuitos):

data/pedagios.json   praças de pedágio federais (ANTT) com localização e valor aproximado para carro.
                     Valor = receita da praça / tráfego em "veículos equivalentes" (carro = 1), mediana dos
                     últimos meses. É uma estimativa: descontos de tag e cobrança em um só sentido mudam o valor.
data/municipios.json todos os municípios do Brasil (IBGE) com coordenadas.
"""
import csv, io, json, math, os, re, statistics, sys, unicodedata, urllib.request
from collections import defaultdict
from datetime import date

UA = {"User-Agent": "Mozilla/5.0 (dados abertos)"}
B = "https://dados.antt.gov.br/dataset/"
CKAN = "https://dados.antt.gov.br/api/3/action/package_show?id="


def get(url, timeout=300):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
                return r.read()
        except Exception as e:
            print("  tentativa", attempt + 1, "falhou:", url.rsplit("/", 1)[-1], e)
    return None


def text_of(raw):
    for enc in ("utf-8-sig", "cp1252", "latin-1"):
        try:
            return raw.decode(enc)
        except Exception:
            continue
    return raw.decode("latin-1", "replace")


def csv_rows(raw):
    text = text_of(raw)
    sep = ";" if text[:3000].count(";") > text[:3000].count(",") else ","
    return list(csv.DictReader(io.StringIO(text), delimiter=sep))


def num(s):
    s = (s or "").strip().replace('"', "")
    if not s:
        return None
    if "," in s:
        s = s.replace(".", "").replace(",", ".")
    try:
        return float(s)
    except ValueError:
        return None


def fold(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def tokens(s):
    stop = {"praca", "p", "pe", "de", "do", "da", "dos", "das", "br", "km", "pr", "sp", "free", "flow",
            "freeflow", "decrescente", "crescente", "sul", "norte", "aux", "validador", "principal"}
    return {t for t in fold(s).split() if t not in stop and not t.isdigit() and len(t) > 1}


def dist_km(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(h))


def resources(package):
    raw = get(CKAN + package, 60)
    if not raw:
        return []
    return json.loads(raw)["result"]["resources"]


# ---------- Praças (localização) ----------
print("Praças…")
loc_url = next((r["url"] for r in resources("praca-de-pedagio") if (r.get("format") or "").upper() == "CSV"), None)
pracas = [p for p in csv_rows(get(loc_url)) if (p.get("situacao") or "").lower().startswith("ativ")]
print(" ativas:", len(pracas))

# ---------- Receita por praça (mês a mês, com lat/lon) ----------
year = date.today().year
receitas = []
rec_res = resources("receita-por-praca")
for y in (year, year - 1):
    for r in rec_res:
        name = (r.get("name") or "") + " " + (r.get("url") or "")
        if str(y) in name and (r.get("format") or "").upper() == "JSON":
            raw = get(r["url"])
            if raw and len(raw) > 1000:
                data = json.loads(text_of(raw))
                items = next(iter(data.values())) if isinstance(data, dict) else data
                for it in items:
                    receitas.append(it)
                print(" receita", y, len(items))
    if receitas:
        rec_year = y
        break
else:
    rec_year = None

# ---------- Tráfego equivalente mensal (mesmo ano) ----------
volume = defaultdict(float)  # (concessionaria, praca, mes) -> veículos equivalentes
if rec_year:
    for r in resources("volume-trafego-equivalente-praca-pedagio"):
        url = r.get("url") or ""
        if str(rec_year) in url and "mensal" in url and url.endswith(".csv"):
            raw = get(url, 600)
            if raw:
                for row in csv_rows(raw):
                    key = (fold(row.get("concessionaria")), row.get("praca", ""), (row.get("mes_ano") or "").strip())
                    volume[key] += num(row.get("volume_veiculo_equivalente")) or 0
            print(" volume linhas agregadas:", len(volume))
            break

# Nomes de praça do arquivo de volume, por concessionária
vol_pracas = defaultdict(set)
for (conc, praca, _mes) in volume:
    vol_pracas[conc].add(praca)


def best_volume_name(conc, praca_name):
    want = tokens(praca_name)
    code = re.findall(r"\bp\s?0?(\d+)\b", fold(praca_name))
    best, score = None, 0
    for cand in vol_pracas.get(conc, ()):
        s = len(want & tokens(cand)) * 2
        if code and code == re.findall(r"\bp\s?0?(\d+)\b", fold(cand)):
            s += 3
        if s > score:
            best, score = cand, s
    return best if score >= 2 else None


# Tarifa estimada por praça da receita (mediana dos últimos 4 meses com dados)
tarifas = []  # (lat, lon, conc, valor)
by_praca = defaultdict(list)
for it in receitas:
    by_praca[(fold(it.get("Concessionaria")), it.get("Praca_de_pedagio"))].append(it)
for (conc, praca), items in by_praca.items():
    vname = best_volume_name(conc, praca)
    if not vname:
        continue
    vals = []
    for it in sorted(items, key=lambda x: (x.get("Mes_ano") or "")[-4:] + (x.get("Mes_ano") or "")[:2])[-4:]:
        receita = num(it.get("Receita_Praca_de_Pedagio"))
        vol = volume.get((conc, vname, (it.get("Mes_ano") or "").strip()))
        if receita and vol and vol > 1000:
            vals.append(receita / vol)
    if vals:
        v = statistics.median(vals)
        lat, lon = num(items[-1].get("Latitude")), num(items[-1].get("Longitude"))
        if 2 <= v <= 60 and lat and lon:
            tarifas.append((lat, lon, conc, v))
print(" tarifas estimadas:", len(tarifas))

# ---------- Junta localização + tarifa ----------
out = []
for p in pracas:
    lat, lon = num(p.get("latitude")), num(p.get("longitude"))
    if not lat or not lon:
        continue
    conc = fold(p.get("concessionaria"))
    nome = (p.get("praca_de_pedagio") or "").strip().rstrip("_").strip()
    valor = None
    near = [(dist_km((lat, lon), (t[0], t[1])), t[3]) for t in tarifas if t[2] == conc]
    near = [n for n in near if n[0] <= 3]
    if near:
        valor = round(min(near)[1] * 10) / 10
    ff = "free" in fold(nome) or "flow" in fold(nome)
    out.append({
        "nome": nome, "concessionaria": (p.get("concessionaria") or "").strip(), "rodovia": (p.get("rodovia") or "").strip(),
        "uf": p.get("uf"), "lat": round(lat, 6), "lon": round(lon, 6), "freeFlow": ff,
        "sentido": (p.get("sentido") or "").strip(), "valor": valor,
    })

os.makedirs("data", exist_ok=True)
with open("data/pedagios.json", "w", encoding="utf-8") as f:
    json.dump({"atualizado": date.today().isoformat(), "fonte": "ANTT (dados abertos)", "anoReceita": rec_year,
               "pracas": out}, f, ensure_ascii=False, separators=(",", ":"))
print("pedagios.json:", len(out), "praças,", sum(1 for o in out if o["valor"]), "com valor")
for o in out:
    if o["uf"] == "PR":
        print("  PR", o["nome"], "|", o["rodovia"], "|", o["valor"], "| freeflow" if o["freeFlow"] else "")

# ---------- Municípios (IBGE + coordenadas) ----------
print("Municípios…")
coords = {}
raw = get("https://raw.githubusercontent.com/kelvins/municipios-brasileiros/main/csv/municipios.csv")
for row in csv_rows(raw):
    coords[row["codigo_ibge"]] = (num(row["latitude"]), num(row["longitude"]))
ibge = json.loads(get("https://servicodados.ibge.gov.br/api/v1/localidades/municipios"))
mun = []
for m in ibge:
    uf = (((m.get("microrregiao") or {}).get("mesorregiao") or {}).get("UF") or {}).get("sigla") \
        or (((m.get("regiao-imediata") or {}).get("regiao-intermediaria") or {}).get("UF") or {}).get("sigla")
    c = coords.get(str(m["id"]))
    if uf and c and c[0] is not None:
        mun.append([m["nome"], uf, round(c[0], 4), round(c[1], 4)])
mun.sort(key=lambda x: (x[1], fold(x[0])))
with open("data/municipios.json", "w", encoding="utf-8") as f:
    json.dump({"atualizado": date.today().isoformat(), "municipios": mun}, f, ensure_ascii=False, separators=(",", ":"))
print("municipios.json:", len(mun))
if len(mun) < 5000 or len(out) < 100:
    sys.exit("dados incompletos")
