"""Gera dois arquivos para o app (dados abertos e gratuitos):

data/pedagios.json   praças de pedágio federais (ANTT) com localização e valor aproximado para carro.
                     Valor = receita da praça / tráfego em "veículos equivalentes" (carro = 1), mediana dos
                     últimos meses. É uma estimativa: descontos de tag e cobrança em um só sentido mudam o valor.
data/municipios.json todos os municípios do Brasil (IBGE) com coordenadas.
"""
import csv, io, json, math, os, re, statistics, sys, time, unicodedata, urllib.request
from collections import defaultdict
from datetime import date

UA = {"User-Agent": "Mozilla/5.0 (dados abertos)"}
B = "https://dados.antt.gov.br/dataset/"
CKAN = "https://dados.antt.gov.br/api/3/action/package_show?id="


def get(url, timeout=300, tries=3):
    if not url:
        return None
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
                data = r.read()
                print("  baixado", url.rsplit("/", 1)[-1][:60], len(data) // 1024, "KB", r.headers.get("Content-Type"))
                if data[:200].lstrip().lower().startswith((b"<!doctype", b"<html")):
                    print("  (veio página HTML, não dados):", data[:300])
                    time.sleep(10)
                    continue
                return data
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


# Endereços conhecidos (reserva, caso a busca do portal da ANTT não responda)
FALLBACK = {
    "praca-de-pedagio": [{"format": "CSV", "name": "praças", "url": B + "a7e1e12d-f8e8-40cd-bc1f-57973a4a4a6d/resource/9aa29243-c54c-4084-bc3d-c44a75c9bd7e/download/dados-dos-praas-de-pedgio.csv"}],
    "receita-por-praca": [
        {"format": "JSON", "name": "receita 2025", "url": B + "5213d6c6-f494-4cb6-93a7-822ee1cae157/resource/5f48cdb3-db1e-427e-b357-65582a42cfce/download/receita_por_praca_2025.json"},
        {"format": "JSON", "name": "receita 2024", "url": B + "5213d6c6-f494-4cb6-93a7-822ee1cae157/resource/5229e70a-87e9-4cbf-b219-130a4f965d5a/download/receita_por_praca_2024.json"},
    ],
    "volume-trafego-equivalente-praca-pedagio": [
        {"format": "CSV", "name": "volume 2026", "url": B + "f3ea994f-7435-4867-83b4-1ee5d1debbce/resource/a3e2858b-2f2a-4db7-9aa7-f18f766b1ac8/download/volume-trafego-equivalente-praca-pedagio-2026_mensal_consolidado.csv"},
        {"format": "CSV", "name": "volume 2025", "url": B + "f3ea994f-7435-4867-83b4-1ee5d1debbce/resource/31621b74-678b-4411-9912-2f9ccc831604/download/volume-trafego-equivalente-praca-pedagio-2025_mensal_consolidado.csv"},
    ],
}


def resources(package):
    """Arquivos de um conjunto da ANTT: consulta rápida ao portal (para achar arquivos novos)
    somada aos endereços conhecidos (que funcionam mesmo se o portal estiver lento)."""
    found = []
    raw = get(CKAN + package, 25, tries=1)
    if raw:
        try:
            found = json.loads(raw)["result"].get("resources", [])
        except Exception as e:
            print("  resposta inesperada", e)
    known = FALLBACK.get(package, [])
    urls = {r.get("url") for r in found}
    return found + [r for r in known if r["url"] not in urls]


# ---------- Praças (localização) ----------
print("Praças…")
loc_url = next((r["url"] for r in resources("praca-de-pedagio") if (r.get("format") or "").upper() == "CSV"), None)
loc_raw = get(loc_url) or get(FALLBACK["praca-de-pedagio"][0]["url"])
pracas = [p for p in csv_rows(loc_raw) if (p.get("situacao") or "").lower().startswith("ativ")] if loc_raw else []
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
    # Cruza pela localização (as concessionárias mudam de nome; a praça continua no mesmo lugar).
    near = [(dist_km((lat, lon), (t[0], t[1])), t[3]) for t in tarifas]
    near = [n for n in near if n[0] <= 2.5]
    if near:
        valor = round(min(near)[1] * 10) / 10
    ff = "free" in fold(nome) or "flow" in fold(nome)
    out.append({
        "nome": nome, "concessionaria": (p.get("concessionaria") or "").strip(), "rodovia": (p.get("rodovia") or "").strip(),
        "uf": p.get("uf"), "lat": round(lat, 6), "lon": round(lon, 6), "freeFlow": ff,
        "sentido": (p.get("sentido") or "").strip(), "valor": valor,
    })

# Valores oficiais conferidos no site da concessionária (têm prioridade sobre a estimativa).
OFICIAIS = [
    # Motiva Paraná: free flow de Mauá da Serra e de Tamarana (PR-445, "P7 Londrina"), R$ 10,80 para carro
    # https://rodovias.motiva.com.br/parana/noticias/2026/julho/cliente-com-tag-tem-direito-a-descontos-no-pedagio-eletronico-da/
    {"conc": "motiva parana", "nome": "maua da serra", "valor": 10.80},
    {"conc": "motiva parana", "nome": "p7 londrina", "valor": 10.80},
]
for o in out:
    o["oficial"] = False
    for item in OFICIAIS:
        if item["conc"] in fold(o["concessionaria"]) and item["nome"] in fold(o["nome"]):
            o["valor"], o["oficial"] = item["valor"], True

# Praças sem receita própria (free flow e concessões novas): média da concessionária; se não houver, média do estado.
by_conc, by_uf = defaultdict(list), defaultdict(list)
for o in out:
    if o["valor"]:
        by_conc[fold(o["concessionaria"])].append(o["valor"])
        by_uf[o["uf"]].append(o["valor"])
all_values = [o["valor"] for o in out if o["valor"]]
for o in out:
    o["estimado"] = None
    if o["valor"]:
        continue
    conc_vals = by_conc.get(fold(o["concessionaria"]))
    uf_vals = by_uf.get(o["uf"]) or all_values
    if conc_vals:
        o["valor"], o["estimado"] = round(statistics.median(conc_vals) * 10) / 10, "concessionaria"
    elif uf_vals:
        o["valor"], o["estimado"] = round(statistics.median(uf_vals) * 10) / 10, "estado"

os.makedirs("data", exist_ok=True)
if len(out) >= 100:
    with open("data/pedagios.json", "w", encoding="utf-8") as f:
        json.dump({"atualizado": date.today().isoformat(), "fonte": "ANTT (dados abertos)", "anoReceita": rec_year,
                   "pracas": out}, f, ensure_ascii=False, separators=(",", ":"))
    print("pedagios.json:", len(out), "praças,", sum(1 for o in out if o["valor"]), "com valor")
else:
    print("ANTT indisponível agora: pedagios.json mantido como estava")

# ---------- Municípios (IBGE + coordenadas) ----------
print("Municípios…")
try:
    coords = {}
    for row in csv_rows(get("https://raw.githubusercontent.com/kelvins/municipios-brasileiros/main/csv/municipios.csv")):
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
    if len(mun) >= 5000:
        with open("data/municipios.json", "w", encoding="utf-8") as f:
            json.dump({"atualizado": date.today().isoformat(), "municipios": mun}, f, ensure_ascii=False, separators=(",", ":"))
        print("municipios.json:", len(mun))
    else:
        print("lista de municípios incompleta: mantida a anterior")
except Exception as e:
    print("IBGE indisponível agora:", e)
