#!/usr/bin/env python3
"""
Consolidated SAP User & Role Assignment Conversion Script
Single-command converter: reads a unified User Excel file (e.g. Assign_User.xlsx)
and generates BOTH required flat CSV files in a single pass:
1. <stem>_01_Create_converted.csv -> for ABAP Z_USER_01_CREATE
2. <stem>_02_Assign_converted.csv -> for ABAP Z_USER_02_ASSIGN_ROLE

Usage:
    python scripts/convert_user.py [input_excel_file] [--output-dir <directory>]

Examples:
    python scripts/convert_user.py excel-working/Assign_User.xlsx
    npm run convert:user -- excel-working/Assign_User.xlsx
    npm run convert:user
"""

import os
import sys
import argparse

# Ensure local script directory is on sys.path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

from convert_user_01_create import convert_user_01_create
from convert_user_02_assign import convert_user_02_assign


def resolve_default_file():
    """Finds default input file if none is explicitly specified."""
    candidates = [
        os.path.join("excel-working", "Assign_User.xlsx"),
        os.path.join("excel-working", "User.xlsx"),
        "Assign_User.xlsx",
        "User.xlsx",
        os.path.join("excel-templates", "Template_Assign_User.xlsx"),
        os.path.join("excel-templates", "Assign_User.xlsx"),
        os.path.join("excel-templates", "Template_User.xlsx"),
        os.path.join("excel-working", "User_Assign.xlsx"),
        "User_Assign.xlsx",
        os.path.join("excel-working", "Template_User.xlsx"),
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def convert_user_all(input_path=None, output_dir=None):
    """
    Executes both User Creation (01) and Role Assignment (02) conversions
    from a single Excel file (or default file).
    """
    if not input_path:
        input_path = resolve_default_file()

    if not input_path:
        # Check if legacy separate templates exist
        t1 = os.path.join("excel-templates", "Template_User_01_Create.xlsx")
        t2 = os.path.join("excel-templates", "Template_User_02_Assign.xlsx")
        if os.path.exists(t1) and os.path.exists(t2):
            print(f"[INFO] Consolidated file not found. Falling back to separate templates: {t1} & {t2}")
            r1, c1 = convert_user_01_create(t1, output_dir)
            r2, c2 = convert_user_02_assign(t2, output_dir)
            print_final_summary(f"{t1} & {t2}", r1, c1, r2, c2)
            return True

        print("[ERROR] No input Excel file provided or found in default locations.")
        print("Usage: python scripts/convert_user.py <path_to_excel_file>")
        print("Example: python scripts/convert_user.py excel-working/Assign_User.xlsx")
        sys.exit(1)

    if not os.path.splitext(input_path)[1]:
        input_path = input_path + ".xlsx"

    if not os.path.exists(input_path):
        print(f"[ERROR] Input file does not exist: {input_path}")
        sys.exit(1)

    print("=" * 70)
    print("🚀 CONSOLIDATED SAP USER CONVERSION")
    print(f"📁 Input File: {input_path}")
    print("=" * 70)

    # 1. Convert User Creation Data (01_Create)
    print("\n▶ [STEP 1/3] Converting User Master Data (Z_USER_01_CREATE)...")
    out_create, count_create = convert_user_01_create(input_path, output_dir)

    # 2. Convert User Default Parameters (if present)
    print("\n▶ [STEP 2/3] Checking User Default Parameters (Z_USER_01_CREATE)...")
    out_param, count_param = None, 0
    try:
        from convert_user_matrix_01_create import convert_user_matrix_01_parameter
        out_param, count_param = convert_user_matrix_01_parameter(input_path, output_dir)
    except Exception as e:
        print(f"[INFO] No parameter sheet converted: {e}")

    # 3. Convert Role Assignment Matrix (02_Assign)
    print("\n▶ [STEP 3/3] Converting Role Assignment Matrix (Z_USER_02_ASSIGN_ROLE)...")
    out_assign, count_assign = convert_user_02_assign(input_path, output_dir)

    # Final Combined Summary
    print_final_summary(input_path, out_create, count_create, out_assign, count_assign, out_param, count_param)
    return True


def print_final_summary(input_path, out_create, count_create, out_assign, count_assign, out_param=None, count_param=0):
    num_files = 3 if out_param else 2
    print("\n" + "=" * 70)
    print(f"✅ USER CONVERSION COMPLETED SUCCESSFULLY ({num_files} CSV FILES READY)")
    print("=" * 70)
    print(f"📥 Source Excel     : {input_path}")
    print(f"📤 1. User Creation : {out_create}")
    print(f"   └── Rows: {count_create} users (Upload to SAP program Z_USER_01_CREATE)")
    if out_param:
        print(f"📤 2. User Params   : {out_param}")
        print(f"   └── Rows: {count_param} parameters (Loaded onto Z_USER_01_CREATE screen)")
    print(f"📤 {num_files}. Role Assign   : {out_assign}")
    print(f"   └── Rows: {count_assign} assignments (Upload to SAP program Z_USER_02_ASSIGN_ROLE)")
    print("=" * 70)
    print("💡 Recommended SAP Run Order:")
    print("   1. Run Z_USER_01_CREATE with file (1) to create/update users and generate passwords.")
    if out_param:
        print("      (Selection screen parameter CSV (2) can be loaded to set default user parameters).")
    print(f"   2. Run Z_USER_02_ASSIGN_ROLE with file ({num_files}) to assign single/composite roles to users.")
    print("=" * 70 + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert SAP User & Role Assignment Excel to 2 CSV files.")
    parser.add_argument("input_file", nargs="?", default=None, help="Path to input Excel file (e.g. Assign_User.xlsx)")
    parser.add_argument("--output-dir", "-o", default=None, help="Custom output directory for converted CSV files")
    args = parser.parse_args()

    convert_user_all(args.input_file, args.output_dir)
