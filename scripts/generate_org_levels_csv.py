import json
import csv
import os

input_file = r'C:\Users\luongdk1\.gemini\antigravity\brain\82adca0e-533e-4691-beef-c08324c02aff\.system_generated\steps\2998\output.txt'
output_csv = r'd:\PROJECTS\SAPABAP\Org_Levels.csv'

with open(input_file, 'r', encoding='utf-8') as f:
    data = json.load(f)

# Priority order as shown in user's image
img_priority = [
    '$BUKRS',  # Company Code
    '$BUNIT',  # Consolidation Unit
    '$DIMEN',  # View
    '$EKGRP',  # Purchasing Group
    '$EKORG',  # Purchasing Organization
    '$FIKRS',  # FM area
    '$FKBER',  # Functional Area
    '$GSBER',  # Business Area
    '$KOART',  # Account Type
    '$KOKRS',  # Controlling Area
    '$PRCTR',  # Profit Centers
    '$SPART',  # Division
    '$VKORG',  # Sales Organization
    '$VTWEG',  # Distribution Channel
    '$WERKS',  # Plant
    '$ERKRS',  # Operating Concern
    '$PLVAR',  # Plan Version
    '$ARBPL',  # Work Center
    '$VSTEL',  # Shipping Point
]

sap_rows = data['rows']
# Dict by varbl
sap_map = {r['VARBL']: r['VTEXT'] for r in sap_rows}

# Prepare ordered rows
ordered_items = []
seen = set()

# 1. Add image priority items first
for var in img_priority:
    if var in sap_map:
        ordered_items.append((sap_map[var], var))
        seen.add(var)

# 2. Add all other SAP Org Levels sorted by Description
remaining = []
for r in sap_rows:
    var = r['VARBL']
    if var not in seen:
        remaining.append((r['VTEXT'], var))
        seen.add(var)

remaining.sort(key=lambda x: x[0].lower())
ordered_items.extend(remaining)

print(f"Total Org Levels extracted: {len(ordered_items)}")

# Write to CSV
with open(output_csv, 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerow(['Org Level Description', 'Org Level Variable'])
    for desc, var in ordered_items:
        writer.writerow([desc, var])

print(f"Successfully generated: {output_csv}")
