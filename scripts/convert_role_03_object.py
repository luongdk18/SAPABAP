#!/usr/bin/env python3
"""
Convert Roles Authorization Objects and Activities Excel matrix to normalized flat row format for SAP upload.
References Object_Levels.csv for standard SAP Authorization Objects & Fields (OBJECT-FIELD).

Iterates column by column (Object-Field):
For each Object-Field, loops through all Roles to output:
1. Role
2. object-field
3. value

Output:
- <parent_dir>/converted/<stem>_converted.csv (UTF-8 with BOM for SAP GUI / BAPI import)

Usage:
    python scripts/convert_role_03_object.py [input_excel_file] [object_levels_csv_file]

Example:
    python scripts/convert_role_03_object.py excel-templates/Template_Role_03_Object.xlsx
    -> Outputs: excel-templates/converted/Template_Role_03_Object_converted.csv
"""

import os
import sys
import re
import csv
import glob
import openpyxl

# --- Safe Console Output on Windows ---
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')


# --- Object Levels Reference Loader ---
def load_object_levels_reference(object_levels_path):
    """
    Loads Object_Levels.csv into mapping dictionaries:
    - by_field: 'OBJECT-FIELD' -> 'OBJECT-FIELD'
    - by_desc: 'Object Description' (lowercase) -> 'OBJECT-FIELD'
    """
    if not os.path.exists(object_levels_path):
        return {}, {}

    field_set = set()
    desc_map = {}

    try:
        with open(object_levels_path, 'r', encoding='utf-8-sig', errors='replace') as f:
            reader = csv.DictReader(f)
            for row in reader:
                obj_field = row.get('Object-Field', '').strip().upper()
                obj_desc = row.get('Object Description', '').strip().lower()

                if obj_field:
                    field_set.add(obj_field)
                if obj_desc and obj_field:
                    desc_map[obj_desc] = obj_field
    except Exception as e:
        print(f"[WARN] Could not load Object_Levels.csv: {e}")

    return field_set, desc_map


def match_object_field(header_text, valid_fields, desc_map):
    """
    Matches an Excel column header string to an SAP Object-Field (e.g. F_BKPF_BUK-ACTVT).
    Supported formats:
    - Accounting Document: CoCode (F_BKPF_BUK-BUKRS) -> F_BKPF_BUK-BUKRS
    - Direct: F_BKPF_BUK-ACTVT -> F_BKPF_BUK-ACTVT
    - Colon/Dot separated: F_BKPF_BUK:ACTVT / F_BKPF_BUK.ACTVT -> F_BKPF_BUK-ACTVT
    - Exact/Normalized description match in Object_Levels.csv
    """
    text = header_text.strip()
    if not text:
        return None

    # Priority 1: Direct parenthesized object-field: (OBJECT-FIELD) or (OBJECT:FIELD) or (OBJECT.FIELD)
    paren_match = re.search(r'\(([A-Za-z0-9_/$]+)\s*[\-:\.]\s*([A-Za-z0-9_/$]+)\)', text)
    if paren_match:
        obj_name = paren_match.group(1).upper()
        fld_name = paren_match.group(2).upper()
        return f"{obj_name}-{fld_name}"

    # Priority 2: Standalone OBJECT-FIELD in header
    clean_text = text.upper().strip()
    dash_match = re.search(r'(?:^|\s)([A-Za-z0-9_/$]+)\s*[\-:\.]\s*([A-Za-z0-9_/$]+)(?:$|\s)', clean_text)
    if dash_match:
        obj_candidate = f"{dash_match.group(1)}-{dash_match.group(2)}"
        return obj_candidate

    # Priority 4: Direct match in Object_Levels.csv description dictionary
    lower_text = text.lower()
    if lower_text in desc_map:
        return desc_map[lower_text]

    # Partial / substring match in description dictionary
    for desc, obj_fld in desc_map.items():
        if lower_text == desc or f"({lower_text})" in desc:
            return obj_fld

    return None


def convert_role_03_object(input_path, object_levels_path=None, output_dir=None):
    """
    Reads Authorization Objects and Activities Excel matrix and converts to normalized flat CSV format.
    Iterates column-by-column across Object-Fields, then row-by-row across Roles.
    Output is saved to <parent_dir>/converted/ by default.
    Columns: Role, object-field, value
    """
    if not os.path.splitext(input_path)[1]:
        input_path = input_path + ".xlsx"

    if not os.path.exists(input_path):
        print(f"[ERROR] Input file not found: {input_path}")
        sys.exit(1)

    # Locate Object_Levels.csv reference
    if not object_levels_path:
        cand_paths = [
            os.path.join(os.path.dirname(input_path), "Object_Levels.csv"),
            os.path.join(os.path.dirname(os.path.dirname(input_path)), "excel-templates", "Object_Levels.csv"),
            os.path.join("excel-templates", "Object_Levels.csv"),
            "Object_Levels.csv"
        ]
        for c in cand_paths:
            if os.path.exists(c):
                object_levels_path = c
                break

    valid_fields, desc_map = load_object_levels_reference(object_levels_path) if object_levels_path else (set(), {})
    if object_levels_path:
        print(f"[INFO] Using Object Levels reference: '{object_levels_path}' ({len(valid_fields)} standard Object-Fields)")

    base_name = os.path.basename(input_path)
    stem, _ = os.path.splitext(base_name)

    out_csv_name = f"{stem}_converted.csv"
    if output_dir is None:
        dir_name = os.path.dirname(input_path) or "."
        output_dir = os.path.join(dir_name, "converted")

    if output_dir.endswith('.csv'):
        out_csv_path = output_dir
        if os.path.dirname(out_csv_path):
            os.makedirs(os.path.dirname(out_csv_path), exist_ok=True)
    else:
        os.makedirs(output_dir, exist_ok=True)
        out_csv_path = os.path.join(output_dir, out_csv_name)

    # Load Workbook
    try:
        wb_in = openpyxl.load_workbook(input_path, data_only=True)
    except Exception as e:
        print(f"[ERROR] Could not read Excel workbook '{input_path}': {e}")
        sys.exit(1)

    target_sheet = None
    for name in wb_in.sheetnames:
        lower_name = name.strip().lower()
        if any(k in lower_name for k in ['object', 'auth', 'activity', 'obj']):
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
    obj_columns = []

    for col in range(1, ws.max_column + 1):
        header_val = str(ws.cell(1, col).value or '').strip()
        if not header_val:
            continue

        header_lower = header_val.lower()
        if role_col is None and any(k in header_lower for k in ['role', 'agr_name', 'name']):
            role_col = col
            continue

        obj_field = match_object_field(header_val, valid_fields, desc_map)
        if obj_field:
            obj_columns.append((col, header_val, obj_field))
        else:
            print(f"[WARN] Col {col} '{header_val}' could not be matched to an SAP Object-Field (OBJECT-FIELD).")

    if role_col is None:
        role_col = 1
        print("[INFO] Fallback: Using Column 1 for Role Names.")

    print(f"\n[INFO] Identified {len(obj_columns)} Object-Field columns to process:")
    for col_idx, hdr, ofld in obj_columns:
        print(f"  - Col {col_idx:2d}: {hdr:40s} -> {ofld}")

    flat_rows = []
    empty_cells_skipped = 0
    cols_processed = 0

    # Column-by-column iteration across Object-Fields
    for col_idx, hdr, obj_field in obj_columns:
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
                'obj_field': obj_field,
                'value': str_val
            })
            col_has_values = True

        if col_has_values:
            cols_processed += 1

    # CSV Export
    try:
        with open(out_csv_path, 'w', newline='', encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            # Standard requested columns: Role, object-field, value
            writer.writerow(["Role", "object-field", "value"])
            for item in flat_rows:
                writer.writerow([item['role_name'], item['obj_field'], item['value']])
    except PermissionError:
        print(f"[ERROR] Permission denied when writing to '{out_csv_path}'. Please close the file in Excel and try again.")
        sys.exit(1)

    # Execution Summary
    print(f"\n--- Execution Summary ---")
    print(f"[OK] Input File       : {input_path}")
    print(f"[OK] Reference File   : {object_levels_path}")
    print(f"[OK] Output CSV       : {out_csv_path} ({len(flat_rows)} data rows)")
    print(f"[OK] Processed Objs   : {cols_processed} Object-Field column(s) populated")
    print(f"[OK] Total Records    : {len(flat_rows)} flat rows generated")
    if empty_cells_skipped > 0:
        print(f"[INFO] Empty Values   : {empty_cells_skipped} empty/null cell(s) skipped")


# Compatibility alias
convert_role_object_excel = convert_role_03_object


# --- CLI Entrypoint ---
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ('-h', '--help'):
        print("Usage: python scripts/convert_role_03_object.py [path_to_excel_file] [object_levels_csv_file]")
        print("Example: python scripts/convert_role_03_object.py excel-templates/Template_Role_03_Object.xlsx")
        sys.exit(0)

    target_files = []
    target_obj_csv = None

    if len(sys.argv) > 1 and not sys.argv[1].endswith('.csv'):
        for arg in sys.argv[1:]:
            if arg.endswith('.csv'):
                target_obj_csv = arg
            else:
                target_files.append(arg)
    elif len(sys.argv) == 2 and sys.argv[1].endswith('.csv'):
        target_obj_csv = sys.argv[1]

    # Auto-discovery if no target files given
    if not target_files:
        patterns = [
            "excel-working/*Role_03_Object*.xlsx",
            "excel-working/*Object*.xlsx",
            "excel-templates/*Role_03_Object*.xlsx",
            "excel-templates/*Object*.xlsx"
        ]
        for pat in patterns:
            for f in glob.glob(pat):
                if not os.path.basename(f).startswith("~$"):
                    target_files.append(f)

    if not target_files:
        print("[INFO] No object matrices found to process.")
        print("Usage: python scripts/convert_role_03_object.py [input_excel_file]")
        sys.exit(0)

    for target in target_files:
        print(f"\n==================================================")
        print(f"  Processing Object Matrix: {target}")
        print(f"==================================================")
        convert_role_03_object(target, target_obj_csv)
