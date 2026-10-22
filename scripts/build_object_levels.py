"""
Builds excel-templates/Object_Levels.csv directly from connected SAP S/4HANA system.
Uses verified ABAP execution output from Z_EXPORT_OBJ_LEVELS.
"""

import os
import csv
import json
from pathlib import Path

BASE_DIR = Path(r"d:\PROJECTS\SAPABAP")
TEMPLATES_DIR = BASE_DIR / "excel-templates"
OUT_CSV = TEMPLATES_DIR / "Object_Levels.csv"
ABAP_OUT_PATH = Path(r"C:\Users\luongdk1\.gemini\antigravity\brain\3393c62f-78b5-4740-9429-6319c68d8dfb\.system_generated\steps\2077\output.txt")

# Standard SAP field descriptions
STANDARD_FIELD_DESCRIPTIONS = {
    'ACTVT': 'Activity',
    'BUKRS': 'Company Code',
    'WERKS': 'Plant',
    'LGORT': 'Storage Location',
    'EKORG': 'Purchasing Organization',
    'EKGRP': 'Purchasing Group',
    'VKORG': 'Sales Organization',
    'VTWEG': 'Distribution Channel',
    'SPART': 'Division',
    'KOKRS': 'Controlling Area',
    'KOART': 'Account Type',
    'PRCTR': 'Profit Center',
    'KOSTL': 'Cost Center',
    'BSART': 'Document Type',
    'BLART': 'Document Type',
    'TCD': 'Transaction Code',
    'BEGRU': 'Authorization Group',
    'BRGRU': 'Authorization Group',
    'GSBER': 'Business Area',
    'BWKEY': 'Valuation Area',
    'ANLKL': 'Asset Class',
    'AFAPL': 'Chart of Depreciation',
    'KTOPL': 'Chart of Accounts',
    'KSTAR': 'Cost Element',
    'AUFART': 'Order Type',
    'VSTEL': 'Shipping Point',
    'DISPO': 'MRP Controller',
    'FKBER': 'Functional Area',
    'BUNIT': 'Consolidation Unit',
    'CONGR': 'Consolidation Group',
    'PERSA': 'Personnel Area',
    'PERSG': 'Employee Group',
    'PERSK': 'Employee Subgroup',
    'CLASS': 'User Group',
    'IWERK': 'Maintenance Planning Plant',
    'SWERK': 'Maintenance Plant',
    'KKBER': 'Credit Control Area',
    'KLVAR': 'Costing Variant',
    'LGNUM': 'Warehouse Number',
    'LGTYP': 'Storage Type',
    'VKBUR': 'Sales Office',
    'VKGRP': 'Sales Group',
    'TPLST': 'Transportation Planning Point',
    'RLDNR': 'Ledger',
    'KTRAT': 'Cost Object Category',
    'ASPET': 'Aspect',
    'DIMEN': 'View',
    'PLVAR': 'Plan Version',
    'BUPLA': 'Business Place',
    'SEGMENT': 'Segment',
}

def build_object_levels():
    print(f"[*] Reading ABAP output from: {ABAP_OUT_PATH}")
    with open(ABAP_OUT_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)

    output_text = data.get('output', '')
    lines = output_text.splitlines()

    records = []
    seen = set()

    for line in lines:
        if '###' not in line:
            continue
        parts = [p.strip() for p in line.split('###')]
        if len(parts) < 5:
            continue

        obj_name = parts[0]
        fld_name = parts[1]
        obj_class = parts[2]
        obj_desc = parts[3]
        class_desc = parts[4]

        if not obj_name or not fld_name:
            continue

        pair_key = (obj_name, fld_name)
        if pair_key in seen:
            continue
        seen.add(pair_key)

        obj_field = f"{obj_name}-{fld_name}"
        fld_desc = STANDARD_FIELD_DESCRIPTIONS.get(fld_name, fld_name)

        if obj_desc:
            full_desc = f"{obj_desc} ({fld_desc})"
        else:
            full_desc = f"{obj_name} ({fld_desc})"

        records.append({
            'full_desc': full_desc,
            'obj_field': obj_field,
            'object': obj_name,
            'field': fld_name,
            'fld_desc': fld_desc,
            'obj_desc': obj_desc,
            'obj_class': obj_class,
            'class_desc': class_desc
        })

    # Sort logically by Object Class, Object Name, Field Name
    records.sort(key=lambda x: (x['obj_class'], x['object'], x['field']))

    print(f"[+] Total unique Object-Field pairs: {len(records)}")

    # Write CSV
    TEMPLATES_DIR.mkdir(parents=True, exist_ok=True)
    with open(OUT_CSV, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.writer(f)
        writer.writerow([
            "Object Description",
            "Object-Field",
            "Object",
            "Field",
            "Field Description",
            "Object Class",
            "Class Description"
        ])
        for r in records:
            writer.writerow([
                r['full_desc'],
                r['obj_field'],
                r['object'],
                r['field'],
                r['fld_desc'],
                r['obj_class'],
                r['class_desc']
            ])

    size_kb = OUT_CSV.stat().st_size / 1024
    print(f"[+] Successfully wrote {OUT_CSV} ({size_kb:.1f} KB, {len(records)} rows)")

if __name__ == "__main__":
    build_object_levels()
