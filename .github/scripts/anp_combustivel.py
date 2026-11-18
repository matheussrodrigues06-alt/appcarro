#!/usr/bin/env python3
"""Baixa a pesquisa semanal de preços da ANP e gera um resumo por cidade.

Fonte: ANP - Levantamento de Preços de Combustíveis (dados abertos, gratuito).
Saída: JSON pequeno com o preço médio da semana mais recente em cada município.
"""
import csv
import io
import os
import json
import re
import sys
import unicodedata
import urllib.request
from collections import defaultdict
from datetime import datetime, timedelta

PAGE = "https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/serie-historica-de-precos-de-combustiveis"
BASE = "https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/arquivos/shpc/qus/"
KNOWN = [BASE + "ultimas-4-semanas-gasolina-etanol.csv", BASE + "ultimas-4-semanas-diesel-gnv.csv"]
HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; dados-abertos-combustivel/1.0)"}


def fetch(url):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=90) as resp:
        return resp.read()


def norm(text):
    text = unicodedata.normalize("NFKD", text or "")
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", text).strip().upper()


def discover():
    urls = []
    try:
        html = fetch(PAGE).decode("utf-8", "ignore")
        for href in re.findall(r'href="([^"]+?\.csv)"', html):
            if "ultimas-4-semanas" in href or "ultimas_4_semanas" in href:
                urls.append(href if href.startswith("http") else "https://www.gov.br" + href)
    except Exception as exc:  # noqa: BLE001
        print(f"Aviso: não consegui ler a página da ANP ({exc})")
    return list(dict.fromkeys(urls + KNOWN))


PRODUCTS = [
    ("GASOLINA ADITIVADA", "gasolinaAditivada"),
    ("GASOLINA", "gasolina"),
    ("ETANOL", "etanol"),
    ("DIESEL S10", "dieselS10"),
    ("DIESEL", "diesel"),
    ("GNV", "gnv"),
]


def product_key(name):
    n = norm(name)
    for prefix, key in PRODUCTS:
        if n.startswith(prefix):
            return key
    return None


def rows(content):
    try:
        text = content.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = content.decode("latin-1")
    delimiter = ";" if text[:2000].count(";") >= text[:2000].count(",") else ","
    reader = csv.reader(io.StringIO(text), delimiter=delimiter)
    header = [norm(h) for h in next(reader)]

    def col(*needles):
        for i, h in enumerate(header):
            if all(n in h for n in needles):
                return i
        raise KeyError(needles)

    i_uf = col("ESTADO")
    i_city = col("MUNICIPIO")
    i_prod = col("PRODUTO")
    i_date = col("DATA")
    i_price = col("VALOR DE VENDA")
    try:
        i_cnpj = col("CNPJ")
    except KeyError:
        i_cnpj = None

    for r in reader:
        try:
            price = float(r[i_price].strip().replace(".", "").replace(",", ".")) if "," in r[i_price] else float(r[i_price])
            date = datetime.strptime(r[i_date].strip(), "%d/%m/%Y")
        except (ValueError, IndexError):
            continue
        key = product_key(r[i_prod])
        if not key or price <= 0:
            continue
        yield norm(r[i_uf]), norm(r[i_city]), key, date, price, (r[i_cnpj].strip() if i_cnpj is not None else "")


def main(out_path):
    data = []
    for url in discover():
        try:
            content = fetch(url)
            parsed = list(rows(content))
            print(f"{url}: {len(parsed)} linhas")
            data.extend(parsed)
        except Exception as exc:  # noqa: BLE001
            print(f"Aviso: falhou {url} ({exc})")
    if not data:
        print("Nenhum dado baixado da ANP — mantendo o arquivo anterior.")
        sys.exit(1)

    latest = max(d[3] for d in data)
    start = latest - timedelta(days=6)
    prices = defaultdict(list)
    stations = defaultdict(set)
    for uf, city, key, date, price, cnpj in data:
        if date >= start:
            prices[(f"{uf}/{city}", key)].append(price)
            if cnpj:
                stations[f"{uf}/{city}"].add(cnpj)

    cities = defaultdict(dict)
    for (city, key), values in prices.items():
        cities[city][key] = round(sum(values) / len(values), 3)
    for city, cnpjs in stations.items():
        cities[city]["postos"] = len(cnpjs)

    result = {
        "atualizado": latest.strftime("%Y-%m-%d"),
        "periodo": f"{start:%d/%m/%Y} a {latest:%d/%m/%Y}",
        "fonte": "ANP - Levantamento de Preços de Combustíveis",
        "cidades": dict(sorted(cities.items())),
    }
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, separators=(",", ":"))
    print(f"OK: {len(cities)} cidades, semana {result['periodo']}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "data/combustivel.json")
