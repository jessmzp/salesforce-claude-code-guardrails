#!/usr/bin/env python3
"""Generate the dirty legacy seed data and the practice-org overlap records.

Deterministic: no clock, fixed random seed, so reruns give identical files.

Outputs (next to this script's parent folders):
  migration/seed/legacy/customers.csv
  migration/seed/legacy/deals.csv
  migration/seed/practice/overlap-plan.json
  migration/seed/practice/overlap-data.json
"""

import csv
import json
import random
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
PRACTICE_DIR = HERE.parent / "practice"

REPS = [
    "rep.ana@legacyco.example",
    "rep.luis@legacyco.example",
    "rep.sofia@legacyco.example",
    "rep.diego@legacyco.example",
]

# 25 base customers: (first, last, company, email domain)
BASE = [
    ("Carlos", "Mejia", "Grupo Cuscatlan S.A. de C.V.", "grupocuscatlan.example"),
    ("Ana", "Herrera", "Textiles del Pacifico", "textilespacifico.example"),
    ("Roberto", "Alvarado", "Cafe Santa Tecla", "cafesantatecla.example"),
    ("Maria", "Quintanilla", "Distribuidora Apopa", "distapopa.example"),
    ("John", "Miller", "Miller Logistics LLC", "millerlogistics.example"),
    ("Sofia", "Ramirez", "Ramirez Hermanos", "ramirezhnos.example"),
    ("Jorge", "Castillo", "Agroexport Centroamerica", "agroexportca.example"),
    ("Laura", "Gomez", "Gomez & Asociados", "gomezasoc.example"),
    ("David", "Johnson", "Johnson Medical Supply", "johnsonmed.example"),
    ("Patricia", "Flores", "Flores Construcciones", "floresconst.example"),
    ("Miguel", "Torres", "Torres Automotriz", "torresauto.example"),
    ("Elena", "Martinez", "Martinez Pharma", "martinezpharma.example"),
    ("Fernando", "Rivas", "Rivas Seguridad", "rivasseguridad.example"),
    ("Karen", "Smith", "Smith Brothers Packaging", "smithpackaging.example"),
    ("Luis", "Hernandez", "Hernandez Tech", "hernandeztech.example"),
    ("Gabriela", "Ortiz", "Ortiz Alimentos", "ortizalimentos.example"),
    ("Ricardo", "Menendez", "Menendez Energia", "menendezenergia.example"),
    ("Daniela", "Lopez", "Lopez Turismo", "lopezturismo.example"),
    ("Mark", "Davis", "Davis Software Group", "davissoftware.example"),
    ("Claudia", "Santos", "Santos Importaciones", "santosimport.example"),
    ("Andres", "Villalta", "Villalta Plasticos", "villaltaplasticos.example"),
    ("Rebecca", "Wilson", "Wilson Analytics", "wilsonanalytics.example"),
    ("Hector", "Aguilar", "Aguilar Metales", "aguilarmetales.example"),
    ("Monica", "Reyes", "Reyes Educacion", "reyeseducacion.example"),
    ("Pablo", "Chavez", "Chavez Refrigeracion", "chavezrefri.example"),
]

COUNTRY_VARIANTS = [
    "El Salvador", "SV", "el salvador", "USA", "United States", "Mexico", "MX",
]
STATUS_VARIANTS = ["Activo", "active", "ACT", "Inactive", "inactivo"]
REVENUES = [1200000, 850000, 2500000, 4300000, 640000, 15000000, 980000]

PHONES = {
    "sv": ["+503 2222-3333", "7000-1234", "50370001234", "(503) 7777 8888"],
    "us": ["555.123.4567", "(555) 123-4567", "+1 555 123 4567"],
    "mx": ["+52 55 1234 5678", "55-1234-5678"],
}
MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

# Base customers (1-based ids) that also exist in the practice org.
OVERLAP_IDS = [3, 7, 11, 15, 19]
# Practice Account names that differ slightly from the legacy company name.
PRACTICE_ACCOUNT_NAMES = {
    7: "Agroexport Centroamerica SA",
    11: "Torres Automotriz S.A.",
}
# Base customers that get a duplicate row: (base id, dup id)
DUPLICATES = [(7, 26), (12, 27), (20, 28)]
NO_DEAL_IDS = {2, 9, 17, 23}
# Extra deals beyond 2 each (26 customers x 2 = 52 + 8 = 60).
EXTRA_DEALS = {1: 3, 7: 3, 12: 2}

STAGES = (
    ["Won"] * 12 + ["Closed-Won"] * 10 + ["closed won"] * 2 + ["Lost"] * 10
    + ["Open"] * 12 + ["In progress"] * 12 + ["On hold"] * 2
)
OPEN_STAGES = {"Open", "In progress", "On hold"}


def legacy_id(n):
    return f"LEG-{n:03d}"


def country_kind(country):
    c = country.strip().lower()
    if c in ("usa", "united states"):
        return "us"
    if c in ("mexico", "mx"):
        return "mx"
    return "sv"


def fmt_revenue(value, i):
    short = f"{value / 1_000_000:g}M" if value >= 1_000_000 else f"{value // 1000}K"
    forms = [f"${value:,}", short, str(value), short, f"USD {value:,}"]
    return forms[i % len(forms)]


def fmt_since(i):
    year = 2015 + (i * 3) % 9
    month = (i * 5) % 12 + 1
    day = (i * 7) % 28 + 1
    forms = [
        f"{year}-{month:02d}-{day:02d}",
        f"{day:02d}/{month:02d}/{year}",
        f"{month:02d}/{day:02d}/{year}",
        f"{MONTHS[month - 1]} {day}, {year}",
        str(year),
    ]
    return forms[i % len(forms)]


def build_customers():
    rows = {}
    for n, (first, last, company, domain) in enumerate(BASE, start=1):
        i = n - 1
        country = COUNTRY_VARIANTS[i % len(COUNTRY_VARIANTS)]
        phones = PHONES[country_kind(country)]
        email = f"{first}.{last}@{domain}".lower()
        # LEG-015 stays in the overlap set but with a different case.
        if n == 15:
            email = f"{first}.{last}@{domain}"
        rows[n] = {
            "Legacy_Id__c": legacy_id(n),
            "Full_Name__c": f"{first} {last}",
            "Company_Name__c": company,
            "Email__c": email,
            "Phone__c": phones[i % len(phones)],
            "Country__c": country,
            "Status__c": "" if n in (10, 19) else STATUS_VARIANTS[i % len(STATUS_VARIANTS)],
            "Customer_Since__c": fmt_since(i),
            "Annual_Revenue__c": "" if n in (4, 22) else fmt_revenue(REVENUES[i % len(REVENUES)], i),
            "Sales_Rep_Email__c": REPS[i % len(REPS)],
        }

    # In-legacy duplicates: same email (one with different case), other fields drift.
    for k, (base_n, dup_n) in enumerate(DUPLICATES):
        src = rows[base_n]
        first, last = src["Full_Name__c"].split(" ", 1)
        dup = dict(src)
        dup["Legacy_Id__c"] = legacy_id(dup_n)
        dup["Full_Name__c"] = f"{first[0]}. {last}" if k == 0 else f"{last}, {first}"
        dup["Phone__c"] = PHONES["sv"][(k + 1) % len(PHONES["sv"])]
        dup["Status__c"] = STATUS_VARIANTS[(base_n + 2) % len(STATUS_VARIANTS)]
        dup["Customer_Since__c"] = fmt_since(base_n + 4)
        if k == 1:
            dup["Email__c"] = src["Email__c"].upper().replace(".EXAMPLE", ".example")
        rows[dup_n] = dup

    # Rows that should fail or be flagged.
    missing = dict(rows[8])
    missing.update({
        "Legacy_Id__c": legacy_id(29),
        "Full_Name__c": "Valeria Campos",
        "Company_Name__c": "Campos Servicios",
        "Email__c": "",
        "Country__c": "El Salvador",
        "Status__c": "Activo",
    })
    rows[29] = missing
    unknown = dict(rows[13])
    unknown.update({
        "Legacy_Id__c": legacy_id(30),
        "Full_Name__c": "T'Challa Udaku",
        "Company_Name__c": "Wakanda Design Group",
        "Email__c": "tchalla@wakandadesign.example",
        "Country__c": "Wakanda",
        "Phone__c": "000-0000",
        "Status__c": "active",
    })
    rows[30] = unknown
    return [rows[n] for n in sorted(rows)]


def build_deals(customers):
    rng = random.Random(20261018)
    stages = STAGES[:]
    rng.shuffle(stages)
    ids = [c["Legacy_Id__c"] for c in customers]
    deals = []
    for n, lid in enumerate(ids, start=1):
        if n in NO_DEAL_IDS:
            continue
        for _ in range(2 + EXTRA_DEALS.get(n, 0)):
            deals.append({"Customer__r.Legacy_Id__c": lid})
    assert len(deals) == 60, len(deals)
    for idx, (deal, stage) in enumerate(zip(deals, stages)):
        amount = 0 if idx == 17 else rng.randrange(2, 1001) * 500
        if stage in OPEN_STAGES:
            close = date(2026, 11, 1).toordinal() + rng.randrange(0, 240)
        else:
            close = date(2023, 1, 1).toordinal() + rng.randrange(0, 1368)
        deal.update({
            "Amount__c": amount,
            "Stage__c": stage,
            "Close_Date__c": date.fromordinal(close).isoformat(),
        })
    return deals


def write_csv(path, rows, fields):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def build_practice(customers):
    by_id = {c["Legacy_Id__c"]: c for c in customers}
    records = []
    for n in OVERLAP_IDS:
        c = by_id[legacy_id(n)]
        first, last = c["Full_Name__c"].split(" ", 1)
        account = PRACTICE_ACCOUNT_NAMES.get(n, c["Company_Name__c"])
        records.append({
            "attributes": {"type": "Account", "referenceId": f"AccountRef{n}"},
            "Name": account,
            "Description": "MIG-PRACTICE-SEED",
            "Contacts": {"records": [{
                "attributes": {"type": "Contact", "referenceId": f"ContactRef{n}"},
                "FirstName": first,
                "LastName": last,
                "Email": c["Email__c"].lower(),
                "Description": "MIG-PRACTICE-SEED",
            }]},
        })
    plan = [{
        "sobject": "Account",
        "saveRefs": True,
        "resolveRefs": True,
        "files": ["overlap-data.json"],
    }]
    PRACTICE_DIR.mkdir(parents=True, exist_ok=True)
    (PRACTICE_DIR / "overlap-data.json").write_text(
        json.dumps({"records": records}, indent=2) + "\n", encoding="utf-8")
    (PRACTICE_DIR / "overlap-plan.json").write_text(
        json.dumps(plan, indent=2) + "\n", encoding="utf-8")


def main():
    customers = build_customers()
    deals = build_deals(customers)
    write_csv(HERE / "customers.csv", customers, [
        "Legacy_Id__c", "Full_Name__c", "Company_Name__c", "Email__c", "Phone__c",
        "Country__c", "Status__c", "Customer_Since__c", "Annual_Revenue__c",
        "Sales_Rep_Email__c",
    ])
    write_csv(HERE / "deals.csv", deals, [
        "Customer__r.Legacy_Id__c", "Amount__c", "Stage__c", "Close_Date__c",
    ])
    build_practice(customers)
    print(f"customers={len(customers)} deals={len(deals)}")


if __name__ == "__main__":
    main()
