#!/usr/bin/env python3
"""
Convert Derived Roles Organizational Levels Excel matrix to normalized flat row format for SAP upload.
References Org_Levels.csv for standard SAP Org Level Variables ($VARBL).

Iterates column by column (Org Level):
For each Org Level, loops through all Derived Roles to output:
- Derived Role
- Org Level Variable ($VARBL)
- Org Value

Outputs CSV file (_converted.csv) for SAP import.

Usage:
    python scripts/convert_role_org_excel.py [input_excel_file] [org_levels_csv_file]

Example:
    python scripts/convert_role_org_excel.py Roles_Derived_Org.xlsx Org_Levels.csv
    -> Outputs: Roles_Derived_Org_converted.csv
"""

import os
import sys
import re
import csv
import openpyxl

# Ensure safe console output on Windows
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# Known SAP standard authorization field to Org Variable mappings (table USORG)
USORG_FIELD_MAP = {
    'CEERKRS': '$ERKRS',
    'COMP_CODE': '$BUKRS',
    'FCLM_BUKRS': '$BUKRS',
    'PUR_ORG': '$EKORG',
    'SLS_ORG': '$VKORG',
    'LOCPLANT': '$WERKS',
    'PLANT_ID': '$WERKS',
    'RAS_PLANT': '$WERKS',
    'CSWRK': '$WERKS',
    'FM_FIKRS': '$FIKRS',
    'K_KEKO': '$KLVAR',
}

# Extended standard FICO authorization field fallbacks
EXTENDED_FIELD_MAP = {
    'cost center': '$KOSTL',
    'segment': '$SEGMENT',
    'business place': '$BUPLA',
    'credit segment': '$KKBER',
}

def load_org_levels_reference(org_levels_path):
    """Loads Org_Levels.csv mapping dictionary."""
    if not os.path.exists(org_levels_path):
        print(f"[WARNING] Reference file not found: {org_levels_path}. Proceeding with built-in mappings.")
        return [], {}, {}

    org_levels_list = []
    by_var = {}
    by_desc = {}

    with open(org_levels_path, 'r', encoding='utf-8-sig') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if len(row) >= 2:
                desc = row[0].strip()
                var = row[1].strip().upper()
                org_levels_list.append((desc, var))
                by_var[var] = desc
                by_desc[desc.lower()] = var

    return org_levels_list, by_var, by_desc

def resolve_org_variable(header_raw, org_levels_list, by_var, by_desc):
    """Resolves an Excel column header into a valid SAP Org Level Variable ($VARBL)."""
    clean_h = ' '.join(str(header_raw).split())

    # 1. Check parenthesized variable or field code: e.g. ($CEERKRS), ($KOKRS), ($BUKRS), (K_KEKO)
    m = re.search(r'\(\$?([A-Za-z0-9_/$]+)\)', clean_h)
    if m:
        raw_code = m.group(1).upper()
        with_dollar = f"${raw_code}" if not raw_code.startswith('$') else raw_code
        if with_dollar in by_var:
            return with_dollar, f"Org_Levels.csv variable: {with_dollar}"
        code_no_dollar = raw_code.lstrip('$')
        if code_no_dollar in USORG_FIELD_MAP:
            mapped_var = USORG_FIELD_MAP[code_no_dollar]
            return mapped_var, f"USORG field mapping: {code_no_dollar} -> {mapped_var}"

    # 2. Match by clean description (without parentheses)
    clean_desc = re.sub(r'\(.*?\)', '', clean_h).strip().lower()

    if clean_desc in by_desc:
        return by_desc[clean_desc], f"Org_Levels.csv exact desc: {clean_desc}"

    # Plural / singular variations
    if f"{clean_desc}s" in by_desc:
        return by_desc[f"{clean_desc}s"], f"Org_Levels.csv plural: {clean_desc}s"
    if clean_desc.endswith('s') and clean_desc[:-1] in by_desc:
        return by_desc[clean_desc[:-1]], f"Org_Levels.csv singular: {clean_desc[:-1]}"

    # Specific common keywords in description
    if 'plant' in clean_desc:
        return '$WERKS', "Org_Levels.csv: Plant -> $WERKS"
    if 'profit center' in clean_desc:
        return '$PRCTR', "Org_Levels.csv: Profit Centers -> $PRCTR"
    if 'operating concern' in clean_desc:
        return '$ERKRS', "Org_Levels.csv: Operating Concern -> $ERKRS"
    if 'controlling area' in clean_desc:
        return '$KOKRS', "Org_Levels.csv: Controlling Area -> $KOKRS"
    if 'company code' in clean_desc:
        return '$BUKRS', "Org_Levels.csv: Company Code -> $BUKRS"
    if 'order type' in clean_desc:
        return '$AUFART', "Org_Levels.csv: Order Type -> $AUFART"
    if 'asset class' in clean_desc:
        return '$ANLKL', "Org_Levels.csv: Asset Class -> $ANLKL"
    if 'costing variant' in clean_desc:
        return '$KLVAR', "Org_Levels.csv: Costing Variant -> $KLVAR"
    if 'shipping point' in clean_desc:
        return '$VSTEL', "Org_Levels.csv: Shipping Point -> $VSTEL"
    if 'distribution channel' in clean_desc:
        return '$VTWEG', "Org_Levels.csv: Distribution Channel -> $VTWEG"
    if 'sales org' in clean_desc:
        return '$VKORG', "Org_Levels.csv: Sales Organization -> $VKORG"
    if 'purchasing org' in clean_desc:
        return '$EKORG', "Org_Levels.csv: Purchasing Organization -> $EKORG"
    if 'purchasing group' in clean_desc:
        return '$EKGRP', "Org_Levels.csv: Purchasing Group -> $EKGRP"

    # 3. Fallback to extended FICO authorization fields
    if clean_desc in EXTENDED_FIELD_MAP:
        return EXTENDED_FIELD_MAP[clean_desc], f"Extended FICO field: {clean_desc}"

    # Fuzzy match in Org_Levels.csv
    for d, v in org_levels_list:
        if d.lower() in clean_desc or clean_desc in d.lower():
            return v, f"Org_Levels.csv fuzzy: '{d}' -> {v}"

    return None, "Unmapped"

def convert_role_org_excel(input_path, org_levels_path=None):
    # Resolve input path
    if not os.path.splitext(input_path)[1]:
        input_path = input_path + ".xlsx"

    if not os.path.exists(input_path):
        print(f"[ERROR] Input file not found: {input_path}")
        sys.exit(1)

    dir_name = os.path.dirname(input_path)
    base_name = os.path.basename(input_path)
    stem, _ = os.path.splitext(base_name)

    # Resolve Org_Levels.csv path
    if not org_levels_path:
        cand_list = [
            os.path.join(dir_name, "Org_Levels.csv") if dir_name else None,
            os.path.join("excel-templates", "Org_Levels.csv"),
            os.path.join(os.path.dirname(__file__), "..", "excel-templates", "Org_Levels.csv"),
            "Org_Levels.csv"
        ]
        for cand in cand_list:
            if cand and os.path.exists(cand):
                org_levels_path = cand
                break
        if not org_levels_path:
            org_levels_path = os.path.join("excel-templates", "Org_Levels.csv")

    out_csv_name = f"{stem}_converted.csv"
    out_csv_path = os.path.join(dir_name, out_csv_name) if dir_name else out_csv_name

    # Load Org_Levels reference
    org_list, by_var, by_desc = load_org_levels_reference(org_levels_path)
    print(f"[INFO] Loaded reference: '{org_levels_path}' ({len(org_list)} Org Levels)")

    wb_in = openpyxl.load_workbook(input_path, data_only=True)

    # Locate 'DERIVED ROLES' sheet or fallback
    target_sheet = None
    for name in wb_in.sheetnames:
        if name.strip().lower() == "derived roles":
            target_sheet = wb_in[name]
            break

    if target_sheet is None:
        target_sheet = wb_in.active
        print(f"[INFO] Using active sheet '{target_sheet.title}'.")
    else:
        print(f"[INFO] Processing sheet: '{target_sheet.title}'")

    ws = target_sheet

    # Analyze and map columns (Col 2 to ws.max_column)
    mapped_columns = []
    unmapped_columns = []

    print("\n--- Column Resolution ---")
    for col in range(2, ws.max_column + 1):
        raw_header = ws.cell(1, col).value
        if raw_header is None:
            continue
        var, reason = resolve_org_variable(raw_header, org_list, by_var, by_desc)
        clean_name = ' '.join(str(raw_header).split())
        if var:
            mapped_columns.append((col, var, clean_name))
            print(f"  Col {col:2d}: {clean_name:<30} -> {var:<10} ({reason})")
        else:
            unmapped_columns.append((col, clean_name))
            print(f"  Col {col:2d}: {clean_name:<30} -> [SKIPPED] ({reason})")

    if unmapped_columns:
        print(f"[WARNING] {len(unmapped_columns)} column(s) could not be mapped to an Org Variable and will be skipped.")

    # Read Derived Role rows and convert in column-major order as requested
    flat_rows = []
    cols_processed = 0
    empty_cells_skipped = 0

    # Outer loop: Org Level Columns (Col 2..N)
    for col, org_var, col_name in mapped_columns:
        col_emitted = 0
        # Inner loop: Derived Role Rows (Row 2..max_row)
        for row in range(2, ws.max_row + 1):
            raw_role = ws.cell(row, 1).value
            if not raw_role:
                continue
            role_name = str(raw_role).strip().upper()

            raw_val = ws.cell(row, col).value
            if raw_val is None:
                empty_cells_skipped += 1
                continue

            val_str = str(raw_val).strip()
            if not val_str:
                empty_cells_skipped += 1
                continue

            flat_rows.append({
                'role_name': role_name,
                'org_var': org_var,
                'org_val': val_str
            })
            col_emitted += 1

        if col_emitted > 0:
            cols_processed += 1

    # Export CSV (UTF-8 with BOM)
    try:
        with open(out_csv_path, 'w', newline='', encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            writer.writerow(["Role Name", "Org Level Variable", "Org Value"])
            for item in flat_rows:
                writer.writerow([item['role_name'], item['org_var'], item['org_val']])
    except PermissionError:
        print(f"[ERROR] Permission denied when writing to '{out_csv_path}'. Please close the file in Excel and try again.")
        sys.exit(1)

    print("\n--- Execution Summary ---")
    print(f"[OK] Input File       : {input_path}")
    print(f"[OK] Reference File   : {org_levels_path}")
    print(f"[OK] Output CSV       : {out_csv_path} ({len(flat_rows)} data rows)")
    print(f"[OK] Processed Orgs   : {cols_processed} Org Level column(s) populated")
    print(f"[OK] Total Records    : {len(flat_rows)} flat rows generated")
    if empty_cells_skipped > 0:
        print(f"[INFO] Empty Values   : {empty_cells_skipped} empty/null cell(s) skipped")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ('-h', '--help'):
        print("Usage: python scripts/convert_role_org_excel.py [path_to_excel_file] [org_levels_csv_file]")
        print("Example: python scripts/convert_role_org_excel.py Roles_Derived_Org.xlsx Org_Levels.csv")
        sys.exit(0)

    target_excel = None
    target_org_csv = None

    if len(sys.argv) > 1:
        target_excel = sys.argv[1]
    if len(sys.argv) > 2:
        target_org_csv = sys.argv[2]

    if not target_excel:
        candidates = [
            os.path.join("excel-working", "FICO_Roles_Derived_Org.xlsx"),
            os.path.join("excel-templates", "Template_Roles_Derived_Org.xlsx"),
            "FICO_Roles_Derived_Org.xlsx",
            "Roles_Derived_Org.xlsx"
        ]
        for cand in candidates:
            if os.path.exists(cand):
                target_excel = cand
                break
        else:
            print("Usage: python scripts/convert_role_org_excel.py <path_to_excel_file> [org_levels_csv_file]")
            print("Example: python scripts/convert_role_org_excel.py Roles_Derived_Org.xlsx Org_Levels.csv")
            sys.exit(1)

    convert_role_org_excel(target_excel, target_org_csv)
