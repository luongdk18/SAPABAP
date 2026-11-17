#!/usr/bin/env python3
"""
Convert Composite Roles Matrix Excel file to flat row format for SAP upload.
Filters member Single Roles where cell value is marked with an indicator ('Y', 'y', 'X', 'x').
If a composite role (column) has no indicator values, generates 1 row with Single Role = 'N/A'.

Output columns:
1. Composite Role Name
2. Composite Role Description
3. Single Role

Output:
- <filename>_converted.csv (UTF-8 with BOM for SAP GUI import)

Usage:
    python scripts/convert_role_04_composite.py [input_excel_file]

Example:
    python scripts/convert_role_04_composite.py excel-templates/Template_Role_04_Composite.xlsx
    -> Outputs: excel-templates/converted/Template_Role_04_Composite_converted.csv
"""

import os
import sys
import csv
import glob
import re
import openpyxl

# --- Safe Console Output on Windows ---
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')


def convert_role_04_composite(input_path, output_dir=None):
    """
    Reads Composite Role matrix Excel file and converts to flat CSV format.
    Row 1: Composite Role Description (preserves exact spacing)
    Row 2: Composite Role Name
    Row 3+: Derived Roles (Column 1) and indicator flags ('Y', 'y', 'X', 'x') (Columns 2..N)
    Output is saved to <parent_dir>/converted/ by default.
    """
    # --- Path & File Resolution ---
    if not os.path.splitext(input_path)[1]:
        input_path = input_path + ".xlsx"

    if not os.path.exists(input_path):
        print(f"[ERROR] Input file not found: {input_path}")
        return False

    base_name = os.path.basename(input_path)
    stem, _ = os.path.splitext(base_name)

    if not stem.endswith("_04_Composite"):
        out_csv_name = f"{stem}_04_Composite_converted.csv"
    else:
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

    # --- Load Workbook ---
    try:
        wb_in = openpyxl.load_workbook(input_path, data_only=True)
    except Exception as e:
        print(f"[ERROR] Could not read Excel workbook '{input_path}': {e}")
        sys.exit(1)

    # Locate target sheet:
    # If consolidated role file (e.g. FICO_Role.xlsx, Template_Role.xlsx), Sheet 3 (Index 2) is Composite Role.
    # If standalone legacy file (e.g. MM_Role_04_Composite.xlsx), find sheet matching 'composite' or use active/Sheet 1.
    is_consolidated = not any(k in stem.lower() for k in ('_01_', '_02_', '_03_', '_04_', '_master', '_derive', '_org', '_object', '_composite'))

    if is_consolidated and len(wb_in.sheetnames) >= 3:
        target_sheet = wb_in.worksheets[2]
        print(f"[INFO] Consolidated file: Using Sheet 3 (Index 2): '{target_sheet.title}' for Composite Role data.")
    else:
        target_sheet = None
        for name in wb_in.sheetnames:
            if 'composite' in name.strip().lower():
                target_sheet = wb_in[name]
                break
        if target_sheet is None:
            target_sheet = wb_in.worksheets[0] if wb_in.worksheets else wb_in.active
            print(f"[INFO] Using sheet: '{target_sheet.title}'.")
        else:
            print(f"[INFO] Processing sheet: '{target_sheet.title}'")

    ws = target_sheet

    roles_flat = []
    roles_with_derived = 0
    roles_without_derived = 0
    no_flag_role_names = []

    # --- Matrix Scanning & Flag Filtering ('Y', 'y', 'X', 'x') ---
    # Iterate over columns (each column starting from col 2 is a Composite Role)
    for col in range(2, ws.max_column + 1):
        cell_desc_val = ws.cell(1, col).value
        role_desc = str(cell_desc_val) if cell_desc_val is not None else ''
        role_name = str(ws.cell(2, col).value or '').strip()

        if not role_name:
            continue

        found_flag = False
        for row in range(3, ws.max_row + 1):
            derived_role = str(ws.cell(row, 1).value or '').strip()
            val = str(ws.cell(row, col).value or '').strip().upper()

            # Filter criteria: accepts Y, y, X, x
            if val in ('Y', 'X') and derived_role:
                roles_flat.append({
                    'role_name': role_name,
                    'role_desc': role_desc,
                    'derived_role': derived_role
                })
                found_flag = True

        # If no indicator ('Y'/'X') was found for this role column, create 1 fallback row with Derived Role = 'N/A'
        if not found_flag:
            roles_flat.append({
                'role_name': role_name,
                'role_desc': role_desc,
                'derived_role': 'N/A'
            })
            roles_without_derived += 1
            no_flag_role_names.append(role_name)
        else:
            roles_with_derived += 1

    # --- CSV Export (UTF-8 with BOM) ---
    try:
        with open(out_csv_path, 'w', newline='', encoding='utf-8-sig') as f:
            writer = csv.writer(f)
            writer.writerow(["Composite Role Name", "Composite Role Description", "Single Role"])
            for item in roles_flat:
                writer.writerow([item['role_name'], item['role_desc'], item['derived_role']])
    except PermissionError:
        print(f"[ERROR] Permission denied when writing to '{out_csv_path}'. Please close the file in Excel and try again.")
        sys.exit(1)

    # --- Execution Summary ---
    total_roles = roles_with_derived + roles_without_derived
    print(f"\n--- Execution Summary ---")
    print(f"[OK] Input File       : {input_path}")
    print(f"[OK] Total Roles      : {total_roles} ({roles_with_derived} with Derived Roles, {roles_without_derived} set to 'N/A')")
    if no_flag_role_names:
        print(f"[INFO] Empty Roles    : {', '.join(no_flag_role_names)} -> assigned 'N/A'")
    print(f"[OK] Output CSV       : {out_csv_path} ({len(roles_flat)} data rows)")


# Compatibility alias
convert_role_composite_excel = convert_role_04_composite


# --- CLI Entrypoint ---
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ('-h', '--help'):
        print("Usage: python scripts/convert_role_04_composite.py [path_to_excel_file]")
        print("Example: python scripts/convert_role_04_composite.py excel-templates/Template_Role_04_Composite.xlsx")
        sys.exit(0)

    target_files = []

    if len(sys.argv) > 1:
        for arg in sys.argv[1:]:
            matches = [m for m in glob.glob(arg) if not os.path.basename(m).startswith('~$')]
            if matches:
                target_files.extend(matches)
            elif not os.path.basename(arg).startswith('~$'):
                target_files.append(arg)
    else:
        # Default candidates lookup in working and template directories
        # Prioritize consolidated *Role*.xlsx, fallback to legacy *_04_Composite.xlsx
        working_consolidated = [f for f in glob.glob(os.path.join("excel-working", "*Role*.xlsx"))
                                if not os.path.basename(f).startswith('~$')
                                and not any(k in os.path.basename(f) for k in ('_01_', '_02_', '_03_', '_04_', '_converted'))]
        working_legacy = [f for f in glob.glob(os.path.join("excel-working", "*_04_Composite*.xlsx"))
                          if not os.path.basename(f).startswith('~$')]
        
        consolidated_stems = {re.sub(r'_?Role.*$', '', os.path.basename(f), flags=re.I).upper() for f in working_consolidated}
        filtered_legacy = [f for f in working_legacy if re.sub(r'_?Role.*$', '', os.path.basename(f), flags=re.I).upper() not in consolidated_stems]
        
        unique_working = sorted(working_consolidated + filtered_legacy)
        
        if unique_working:
            target_files = unique_working
        else:
            tpl_consolidated = [f for f in glob.glob(os.path.join("excel-templates", "*Role*.xlsx"))
                                if not os.path.basename(f).startswith('~$')
                                and not any(k in os.path.basename(f) for k in ('_01_', '_02_', '_03_', '_04_', '_converted'))]
            tpl_legacy = [f for f in glob.glob(os.path.join("excel-templates", "*_04_Composite*.xlsx"))
                          if not os.path.basename(f).startswith('~$')]
            tpl_stems = {re.sub(r'_?Role.*$', '', os.path.basename(f), flags=re.I).upper() for f in tpl_consolidated}
            filtered_tpl = [f for f in tpl_legacy if re.sub(r'_?Role.*$', '', os.path.basename(f), flags=re.I).upper() not in tpl_stems]
            
            unique_templates = sorted(tpl_consolidated + filtered_tpl)
            if unique_templates:
                target_files = unique_templates
            else:
                target_files = ["Template_Role_04_Composite.xlsx"]

    if not target_files:
        print("[ERROR] No input file provided or found in default locations.")
        print("Usage: python scripts/convert_role_04_composite.py <path_to_excel_file>")
        print("Example: python scripts/convert_role_04_composite.py excel-working/MM_Role_04_Composite.xlsx")
        sys.exit(1)

    for tf in target_files:
        print(f"\n==================================================")
        print(f"[RUNNING] Converting Composite Role: {tf}")
        print(f"==================================================")
        convert_role_04_composite(tf)
