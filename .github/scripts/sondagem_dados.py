"""Sondagem 4: receita 2024/2025 (CSV e JSON) e tráfego equivalente 2025."""
import urllib.request

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()

B = "https://dados.antt.gov.br/dataset/"
for u in [
    B + "5213d6c6-f494-4cb6-93a7-822ee1cae157/resource/5f48cdb3-db1e-427e-b357-65582a42cfce/download/receita_por_praca_2025.json",
    B + "5213d6c6-f494-4cb6-93a7-822ee1cae157/resource/e44486e4-f359-4851-b8e9-2ad5b3018c99/download/receita_por_praca_2024.csv",
    B + "f3ea994f-7435-4867-83b4-1ee5d1debbce/resource/31621b74-678b-4411-9912-2f9ccc831604/download/volume-trafego-equivalente-praca-pedagio-2025_mensal_consolidado.csv",
]:
    try:
        raw = get(u)
        print("\n#", u.rsplit("/", 1)[-1], len(raw) // 1024, "KB")
        text = raw.decode("utf-8-sig", "replace")
        print(text[:1500])
        import re
        for m in re.finditer(r"[^\n]*(MOTIVA|EPR|LITORAL PIONEIRO|VIA ARAUC)[^\n]*", text[:3_000_000]):
            print("PR>", m.group(0)[:300]); break
    except Exception as e:
        print("erro", u.rsplit("/", 1)[-1], e)
