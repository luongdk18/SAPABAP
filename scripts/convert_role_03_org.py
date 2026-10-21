#!/usr/bin/env python3
"""
Convert Derived Roles Organizational Levels Excel matrix to normalized flat row format for SAP upload.
References Org_Levels.csv for standard SAP Org Level Variables ($VARBL).

Iterates column by column (Org Level):
For each Org Level, loops through all Derived Roles to output:
1. Role Name (Derived Role)
2. Org Level Variable ($VARBL)
3. Org Value

Output:
- <filename>_converted.csv (UTF-8 with BOM for SAP GUI import)

Usage:
    python scripts/convert_role_03_org.py [input_excel_file] [org_levels_csv_file]

Example:
    python scripts/convert_role_03_org.py excel-templates/Template_Role_03_Org.xlsx excel-templates/Org_Levels.csv
    -> Outputs: excel-templates/Template_Role_03_Org_converted.csv
"""

import os
import sys
import re
import csv
import openpyxl

# --- Safe Console Output on Windows ---
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# --- Authorization Field & Org Variable Mapping Tables ---
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


# --- Org Levels Reference Loader ---
def load_org_levels_reference(org_levels_path):
    """Loads Org_Levels.csv mapping dictionary."""
    if not os.path.exists(org_levels_path):
        return {}

    mapping = {}
    try:
        with open(org_levels_path, 'r', encoding='utf-8-sig', errors='replace') as f:
            reader = csv.DictReader(f)
            for row in reader:
                varbl = row.get('VARBL', '').strip()
                field = row.get('FIELD', '').strip().upper()
                name = row.get('NAME', '').strip().lower()

                if field and varbl:
                    mapping[field] = varbl
                if name and varbl:
                    mapping[name] = varbl
    except Exception as e:
        print(f"[WARN] Could not load Org_Levels.csv: {e}")

    return mapping


def match_org_variable(header_text, org_ref_map):
    """Matches an Excel column header string to an SAP Org Level Variable ($VARBL)."""
    text = header_text.strip()
    if not text:
        return None

    # Priority 1: Direct parenthesized variable in header
    direct_match = re.search(r'\(\$([A-Za-z0-9_]+)\)', text)
    if direct_match:
        return f"${direct_match.group(1).upper()}"

    # Priority 2: Standalone $VAR in header
    dollar_match = re.search(r'\$([A-Za-z0-9_]+)', text)
    if dollar_match:
        return f"${dollar_match.group(1).upper()}"

    # Priority 3: Embedded Field name in parentheses
    paren_field_match = re.search(r'\(([A-Za-z0-9_]+)\)', text)
    if paren_field_match:
        cand_field = paren_field_match.group(1).upper()
        if cand_field in org_ref_map:
            return org_ref_map[cand_field]
        if cand_field in USORG_FIELD_MAP:
            return USORG_FIELD_MAP[cand_field]
        if f"${cand_field}" in org_ref_map.values():
            return f"${cand_field}"

    # Priority 4: Direct Org_Levels.csv or USORG lookup
    clean_upper = text.upper()
    if clean_upper in org_ref_map:
        return org_ref_map[clean_upper]
    if clean_upper in USORG_FIELD_MAP:
        return USORG_FIELD_MAP[clean_upper]

    # Priority 5: Semantic fuzzy substring matching
    lower_text = text.lower()
    for phrase, var in EXTENDED_FIELD_MAP.items():
        if phrase in lower_text:
            return var

    if 'controlling area' in lower_text:
        return '$KOKRS'
    if 'company code' in lower_text:
        return '$BUKRS'
    if 'operating concern' in lower_text:
        return '$ERKRS'
    if 'profit center' in lower_text:
        return '$PRCTR'
    if 'cost center' in lower_text:
        return '$KOSTL'
    if 'business place' in lower_text:
        return '$BUPLA'
    if 'plant' in lower_text or 'valuation area' in lower_text:
        return '$WERKS'
    if 'purchasing org' in lower_text:
        return '$EKORG'
    if 'sales org' in lower_text:
        return '$VKORG'
    if 'segment' in lower_text:
        return '$SEGMENT'
    if 'credit segment' in lower_text:
        return '$KKBER'
    if 'fm area' in lower_text or 'financial management' in lower_text:
        return '$FIKRS'

    return None


def convert_role_03_org(input_path, org_levels_path=None):
    """
    Reads Derived Roles Org Level Excel matrix and converts to normalized flat CSV format.
    Iterates column-by-column across Org Levels, then row-by-row across Derived Roles.
    """
    if not os.path.splitext(input_path)[1]:
        input_path = input_path + ".xlsx"

    if not os.path.exists(input_path):
        print(f"[ERROR] Input file not found: {input_path}")
        sys.exit(1)

    # Locate Org_Levels.csv reference
    if not org_levels_path:
        cand_org = [
            os.path.join(os.path.dirname(input_path), "Org_Levels.csv"),
            os.path.join(os.path.dirname(os.path.dirname(input_path)), "excel-templates", "Org_Levels.csv"),
            os.path.join("excel-templates", "Org_Levels.csv"),
            "Org_Levels.csv"
        ]
        for c in cand_org:
            if os.path.exists(c):
                org_levels_path = c
                break

    org_ref_map = load_org_levels_reference(org_levels_path) if org_levels_path else {}
    if org_levels_path:
        print(f"[INFO] Using Org Levels reference: '{org_levels_path}' ({len(org_ref_map)} mappings)")

    dir_name = os.path.dirname(input_path)
    base_name = os.path.basename(input_path)
    stem, _ = os.path.splitext(base_name)

    out_csv_name = f"{stem}_converted.csv"
    out_csv_path = os.path.join(dir_name, out_csv_name) if dir_name else out_csv_name

    # Load Workbook
    try:
        wb_in = openpyxl.load_workbook(input_path, data_only=True)
    except Exception as e:
        print(f"[ERROR] Could not read Excel workbook '{input_path}': {e}")
        sys.exit(1)

    target_sheet = None
    for name in wb_in.sheetnames:
        if 'derive' in name.strip().lower() or 'org' in name.strip().lower():
            target_sheet = wb_in[name]
            break

    if target_sheet is None:
        target_sheet = wb_in.active
        print(f"[INFO] Using active sheet '{target_sheet.title}'.")
    else:
        print(f"[INFO] Processing sheet: '{target_sheet.title}'")

    ws = target_sheet

    # Identify Role Name column
    role_col = None
    org_columns = []

    for col in range(1, ws.max_column + 1):
        header_val = str(ws.cell(1, col).value or '').strip()
        if not header_val:
            continue

        header_lower = header_val.lower()
        if role_col is None and ('role' in header_lower or 'name' in header_lower):
            role_col = col
            continue

        varbl = match_org_variable(header_val, org_ref_map)
        if varbl:
            org_columns.append((col, header_val, varbl))
        else:
            print(f"[WARN] Col {col} '{header_val}' could not be matched to an SAP Org Variable ($VARBL).")

    if role_col is None:
        role_col = 1
        print("[INFO] Fallback: Using Column 1 for Role Names.")

    print(f"\n[INFO] Identified {len(org_columns)} Org Level columns to process:")
    for col_idx, hdr, var in org_columns:
        print(f"  - Col {col_idx:2d}: {hdr:35s} -> {var}")

    flat_rows = []
    empty_cells_skipped = 0
    cols_processed = 0

    # Column-by-column iteration
    for col_idx, hdr, varbl in org_columns:
        col_has_values = False
        for row in range(2, ws.max_row + 1):
            role_name = str(ws.cell(row, role_col).value or '').strip()
            cell_val = ws.cell(row, col_idx).value

            if not role_name:
                continue

            if cell_val is None:
                empty_cells_skipped += 1
                continue

            str_val = str(cell_val).strip()
            if not str_val:
                empty_cells_skipped += 1
                continue

            flat_rows.append({
                'role_name': role_name,
                'org_var': varbl,
                'org_val': str_val
            })
            col_has_values = True

        if col_has_values:
            cols_processed += 1

    # CSV Export
    try:
        with open(out_csv_path, 'w', newline='', encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            writer.writerow(["Role Name", "Org Level Variable", "Org Value"])
            for item in flat_rows:
                writer.writerow([item['role_name'], item['org_var'], item['org_val']])
    except PermissionError:
        print(f"[ERROR] Permission denied when writing to '{out_csv_path}'. Please close the file in Excel and try again.")
        sys.exit(1)

    # Execution Summary
    print(f"\n--- Execution Summary ---")
    print(f"[OK] Input File       : {input_path}")
    print(f"[OK] Reference File   : {org_levels_path}")
    print(f"[OK] Output CSV       : {out_csv_path} ({len(flat_rows)} data rows)")
    print(f"[OK] Processed Orgs   : {cols_processed} Org Level column(s) populated")
    print(f"[OK] Total Records    : {len(flat_rows)} flat rows generated")
    if empty_cells_skipped > 0:
        print(f"[INFO] Empty Values   : {empty_cells_skipped} empty/null cell(s) skipped")


# Compatibility alias
convert_role_org_excel = convert_role_03_org


# --- CLI Entrypoint ---
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ('-h', '--help'):
        print("Usage: python scripts/convert_role_03_org.py [path_to_excel_file] [org_levels_csv_file]")
        print("Example: python scripts/convert_role_03_org.py excel-templates/Template_Role_03_Org.xlsx excel-templates/Org_Levels.csv")
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
            os.path.join("excel-templates", "Template_Role_03_Org.xlsx"),
            os.path.join("excel-templates", "Template_Roles_Derived_Org.xlsx"),
            "Template_Role_03_Org.xlsx",
            "FICO_Roles_Derived_Org.xlsx",
            "Roles_Derived_Org.xlsx"
        ]
        for cand in candidates:
            if os.path.exists(cand):
                target_excel = cand
                break

    if not target_excel:
        print("[ERROR] No input file provided or found in default locations.")
        print("Usage: python scripts/convert_role_03_org.py <path_to_excel_file> [org_levels_csv_file]")
        print("Example: python scripts/convert_role_03_org.py excel-templates/Template_Role_03_Org.xlsx excel-templates/Org_Levels.csv")
        sys.exit(1)

    convert_role_03_org(target_excel, target_org_csv)
