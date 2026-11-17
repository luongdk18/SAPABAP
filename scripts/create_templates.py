#!/usr/bin/env python3
"""
Generate standardized, masked template files for SAP Role and User upload in 'excel-templates/'.

Generated Files:
1. Template_Role.xlsx (Consolidated 3-sheet Role Workbook)
   - Sheet 1: Master Roles (Menu & TCodes)
   - Sheet 2: Derived Roles & Org/Object Data
   - Sheet 3: Composite Roles
   -> Auto-converts to:
      * Template_Role_01_Master_converted.csv
      * Template_Role_02_Derived_converted.csv
      * Template_Role_03a_Org_Levels_converted.csv
      * Template_Role_03b_Auth_Objects_converted.csv
      * Template_Role_03c_Activity_converted.csv
      * Template_Role_04_Composite_converted.csv
2. Template_User.xlsx (Consolidated User & Role Assignment Matrix)
   - Sheet 1: User Asignment (Demographics + Role Matrix + Anti-spam Note)
   - Sheet 2: User Default (Default SU01 Parameters: Parameter ID, Parameter Value, Description)
   -> Auto-converts to:
      * Template_User_01_Create_converted.csv
      * Template_User_02_Assign_converted.csv
      * Template_User_Create_Parameter_converted.csv

Usage:
    python scripts/create_templates.py
"""

import os
import sys
import csv
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side

# --- Safe Console Output on Windows ---
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# Ensure script directory is in sys.path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

# --- Directory & Style Definitions ---
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "excel-templates")
CONVERTED_DIR = os.path.join(OUT_DIR, "converted")
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(CONVERTED_DIR, exist_ok=True)

header_fill = PatternFill(start_color="1F497D", end_color="1F497D", fill_type="solid")
header_font = Font(name="Calibri", size=11, bold=True, color="FFFFFF")
role_name_fill = PatternFill(start_color="DCE6F1", end_color="DCE6F1", fill_type="solid")
role_name_font = Font(name="Calibri", size=11, bold=True, color="000000")
data_font = Font(name="Calibri", size=11)
center_align = Alignment(horizontal="center", vertical="center")
left_align = Alignment(horizontal="left", vertical="center")
thin_border = Border(
    left=Side(style='thin', color='D9D9D9'),
    right=Side(style='thin', color='D9D9D9'),
    top=Side(style='thin', color='D9D9D9'),
    bottom=Side(style='thin', color='D9D9D9')
)


# --- 1. Consolidated Role Template (Template_Role.xlsx) ---
def create_consolidated_role_template():
    wb = openpyxl.Workbook()

    # -------------------------------------------------------------
    # Sheet 1: Master Roles
    # -------------------------------------------------------------
    ws1 = wb.active
    ws1.title = "Master"

    roles = [
        {"name": "Z_FI_PERIOD_CONTROL", "desc": "GL Period Control", "tcodes": ["OB52", "S_ALR_87003642"]},
        {"name": "Z_FI_GL_MASTER_MAINT", "desc": "GL Master Data Maintenance", "tcodes": ["FS00", "FSP0", "FSS0"]},
        {"name": "Z_FI_JOURNAL_POST", "desc": "General Ledger Journal Posting", "tcodes": ["FB01", "FB02", "FB03", "F-02", "FB50"]},
        {"name": "Z_FI_JOURNAL_DISPLAY", "desc": "General Ledger Journal Display", "tcodes": ["FB03", "FBL3N", "FS10N"]},
        {"name": "Z_FI_AP_INVOICE_PROCESS", "desc": "Accounts Payable Invoice Processing", "tcodes": ["FB60", "FB02", "FB03", "F-53"]},
        {"name": "Z_FI_GL_REPORTS_EMPTY", "desc": "General Ledger Custom Reporting", "tcodes": []}
    ]

    all_tcodes = sorted(list({tc for r in roles for tc in r["tcodes"]}))
    c_hdr = ws1.cell(1, 1, value="TCode / Role")
    c_hdr.font = header_font
    c_hdr.fill = header_fill
    c_hdr.border = thin_border

    for col_idx, r in enumerate(roles, start=2):
        c_desc = ws1.cell(1, col_idx, value=r["desc"])
        c_desc.font = header_font
        c_desc.fill = header_fill
        c_desc.border = thin_border

        c_name = ws1.cell(2, col_idx, value=r["name"])
        c_name.font = role_name_font
        c_name.fill = role_name_fill
        c_name.border = thin_border

    for row_idx, tc in enumerate(all_tcodes, start=3):
        c_tc = ws1.cell(row_idx, 1, value=tc)
        c_tc.font = role_name_font
        c_tc.fill = role_name_fill
        c_tc.border = thin_border

        for col_idx, r in enumerate(roles, start=2):
            val = "X" if tc in r["tcodes"] else ""
            c_val = ws1.cell(row_idx, col_idx, value=val)
            c_val.font = data_font
            c_val.alignment = center_align
            c_val.border = thin_border

    ws1.column_dimensions['A'].width = 18
    for col_letter in ['B', 'C', 'D', 'E', 'F', 'G']:
        ws1.column_dimensions[col_letter].width = 30

    # -------------------------------------------------------------
    # Sheet 2: Derived & Org + Object Levels
    # -------------------------------------------------------------
    ws2 = wb.create_sheet(title="Derived")

    headers_s2 = [
        None, None, None,
        "ACTVT, PS_ACTVT",
        "Operating concern\n($CEERKRS)",
        "Controlling area\n($KOKRS)",
        "Company Code ($BUKRS)",
        "Plant / Valuation Area",
        "Profit Center (C_PROJ_PRC, C_PRPS_PRC)",
        "Cost center",
        "Order type",
        "Asset Class",
        "Segment",
        "Business Place",
        "Credit segment",
        "Costing variant (K_KEKO)",
        "Person Responsible (C_PROJ_VNR-PS_VERNR, C_PRPS_VNR-PS_VERNR)"
    ]

    for col_idx, h in enumerate(headers_s2, start=1):
        if h:
            c = ws2.cell(1, col_idx, value=h)
            c.font = header_font
            c.fill = header_fill
            c.alignment = center_align
            c.border = thin_border

    derived_rows = [
        ("Z_FI_PERIOD_CONTROL", "Z_FI_PERIOD_CONTROL_1000", "GL Period Control - CC 1000",
         "*", "1000", "1000", "1000", "1000", "10000100 - 10009899; ' '", "1000*", "*", "*", "*", "*", "*", "*",
         "00000000; 00000080"),
        ("Z_FI_PERIOD_CONTROL", "Z_FI_PERIOD_CONTROL_2000", "GL Period Control - CC 2000",
         "03, F4", "1000", "1000", "2000", "2000", "' '", "2000*", "*", "*", "*", "*", "*", "*",
         "*"),
        ("Z_FI_GL_MASTER_MAINT", "Z_FI_GL_MASTER_MAINT_1000", "GL Master Data Maint - CC 1000",
         "*", "1000", "1000", "1000", "1000", "10009930; ' '", "1000*", "*", "*", "*", "*", "*", "*",
         "00000000;"),
        (None, None, None,
         None, None, None, None, None, None, "*", None, None, None, None, None, None,
         30),
        ("Z_FI_GL_MASTER_MAINT", "Z_FI_GL_MASTER_MAINT_2000", "GL Master Data Maint - CC 2000",
         "03, F4", "1000", "1000", "2000", "2000", "20000100 - 20009899; ' '", "2000*", "*", "*", "*", "*", "*", "*",
         "*"),
        ("Z_FI_JOURNAL_POST", "Z_FI_JOURNAL_POST_1000", "General Ledger Posting - CC 1000",
         "*", "1000", "1000", "1000", "1000", "1000*", "1000*", "*", "*", "*", "*", "*", "*",
         "*"),
        ("Z_FI_JOURNAL_POST", "Z_FI_JOURNAL_POST_2000", "General Ledger Posting - CC 2000",
         "*", "1000", "1000", "2000", "2000", "2000*", "2000*", "*", "*", "*", "*", "*", "*",
         "*"),
    ]

    for row_idx, r_data in enumerate(derived_rows, start=2):
        for col_idx, val in enumerate(r_data, start=1):
            c = ws2.cell(row_idx, col_idx, value=val)
            if col_idx in (1, 2) and val:
                c.font = role_name_font
                c.fill = role_name_fill
            else:
                c.font = data_font
                if col_idx > 3 and val:
                    c.alignment = center_align
            c.border = thin_border

    ws2.column_dimensions['A'].width = 28
    ws2.column_dimensions['B'].width = 32
    ws2.column_dimensions['C'].width = 35
    for col_idx in range(4, 18):
        col_letter = openpyxl.utils.get_column_letter(col_idx)
        ws2.column_dimensions[col_letter].width = 28

    # -------------------------------------------------------------
    # Sheet 3: Composite Roles
    # -------------------------------------------------------------
    ws3 = wb.create_sheet(title="Composite")

    comp_roles = [
        {"name": "Z_FI_COMP_CFO_1000", "desc": "Chief Financial Officer - CC 1000", "singles": ["Z_FI_PERIOD_CONTROL_1000", "Z_FI_JOURNAL_POST_1000"]},
        {"name": "Z_FI_COMP_ACCOUNTANT_1000", "desc": "GL Accountant - CC 1000", "singles": ["Z_FI_JOURNAL_POST_1000", "Z_FI_GL_MASTER_MAINT_1000"]},
        {"name": "Z_FI_COMP_CONTROLLER_1000", "desc": "Financial Controller - CC 1000", "singles": ["Z_FI_PERIOD_CONTROL_1000", "Z_FI_GL_MASTER_MAINT_1000"]},
        {"name": "Z_FI_COMP_EMPTY", "desc": "Empty Composite Role", "singles": []}
    ]

    all_singles = sorted(list({s for cr in comp_roles for s in cr["singles"]}))

    c_hdr3 = ws3.cell(1, 1, value="Single Role / Composite")
    c_hdr3.font = header_font
    c_hdr3.fill = header_fill
    c_hdr3.border = thin_border

    for col_idx, cr in enumerate(comp_roles, start=2):
        c_desc = ws3.cell(1, col_idx, value=cr["desc"])
        c_desc.font = header_font
        c_desc.fill = header_fill
        c_desc.border = thin_border

        c_name = ws3.cell(2, col_idx, value=cr["name"])
        c_name.font = role_name_font
        c_name.fill = role_name_fill
        c_name.border = thin_border

    for row_idx, s in enumerate(all_singles, start=3):
        c_s = ws3.cell(row_idx, 1, value=s)
        c_s.font = role_name_font
        c_s.fill = role_name_fill
        c_s.border = thin_border

        for col_idx, cr in enumerate(comp_roles, start=2):
            val = "X" if s in cr["singles"] else ""
            c_val = ws3.cell(row_idx, col_idx, value=val)
            c_val.font = data_font
            c_val.alignment = center_align
            c_val.border = thin_border

    ws3.column_dimensions['A'].width = 32
    for col_letter in ['B', 'C', 'D', 'E']:
        ws3.column_dimensions[col_letter].width = 32

    xlsx_path = os.path.join(OUT_DIR, "Template_Role.xlsx")
    wb.save(xlsx_path)
    print(f"[OK] Generated consolidated role template: {xlsx_path}")

    # Auto-convert to all converted files
    try:
        from convert_role_01_master import convert_role_01_master
        from convert_role_02_derive import convert_role_02_derive
        from convert_role_03_org_obj import convert_role_03_org_obj
        from convert_role_04_composite import convert_role_04_composite
        convert_role_01_master(xlsx_path)
        convert_role_02_derive(xlsx_path)
        convert_role_03_org_obj(xlsx_path)
        convert_role_04_composite(xlsx_path)
    except Exception as e:
        print(f"[WARN] Could not auto-convert Template_Role.xlsx: {e}")


# --- 2. Consolidated User & Role Matrix Template (Template_User.xlsx & CSVs) ---
def create_consolidated_user_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "User Asignment"

    user_info_headers = ["FULL NAME", "Email", "Phone No.", "Department", "Function", "Initial Password"]
    roles = [
        "CR_COMMON",
        "Z_FI_COMP_CFO_1000",
        "Z_FI_COMP_ACCOUNTANT_1000",
        "Z_FI_COMP_CONTROLLER_1000",
        "Z_MM_PURCHASER_1000"
    ]
    all_headers = user_info_headers + roles + ["Note"]

    for col_idx, h in enumerate(all_headers, start=1):
        c = ws.cell(1, col_idx, value=h)
        c.font = header_font
        c.fill = header_fill
        c.alignment = center_align if (col_idx > len(user_info_headers) and col_idx <= len(user_info_headers) + len(roles)) else left_align

    # Format: [Name, Email, Phone, Dept, Func, Pwd, [Assigned Roles], Note]
    consolidated_users = [
        ["John Doe", "johnd@example.com", "+84 999 999 999", "Finance & Accounting", "Finance Controller", "InitPass@2026", ["CR_COMMON", "Z_FI_COMP_CFO_1000"], None],
        ["Jane Smith", "JaneS@Example.com", "0999999999", "Finance & Accounting", "Senior Accountant", None, ["CR_COMMON", "Z_FI_COMP_ACCOUNTANT_1000"], None],
        ["Alex Johnson", "alexj@example.com", "+1 999 999 9999", "PMU", "Project Director", "Alex#2026Secure", ["CR_COMMON", "Z_FI_COMP_CONTROLLER_1000"], None],
        ["Michael Brown", "michaelb@example.com", "+84 999 999 999", "PMU", "Civil Engineer", None, ["CR_COMMON", "Z_MM_PURCHASER_1000"], "Không gán mail gốc tránh spam"],
        ["Emily Davis", "emilyd", None, "Administration", "HR Specialist", None, ["CR_COMMON"], None],
        ["David Wilson", "davidw@example.com", "0999999999", "Operations", "OM", "DavidW!2026", ["CR_COMMON", "Z_MM_PURCHASER_1000"], None],
        ["Empty User", "empty_user@example.com", None, "Testing", "Tester", None, [], None],
    ]

    for row_idx, u in enumerate(consolidated_users, start=2):
        name, email, phone, dept, func, pwd, assigned_roles, note = u
        row_vals = [name, email, phone, dept, func, pwd]
        for col_idx, val in enumerate(row_vals, start=1):
            c = ws.cell(row_idx, col_idx, value=val)
            c.font = data_font
            c.border = thin_border

        # Role matrix columns
        start_role_col = len(user_info_headers) + 1
        for r_offset, rname in enumerate(roles):
            c_idx = start_role_col + r_offset
            c_val = "X" if rname in assigned_roles else ""
            c = ws.cell(row_idx, c_idx, value=c_val)
            c.font = data_font
            c.alignment = center_align
            c.border = thin_border

        # Note column
        note_col = len(all_headers)
        c_note = ws.cell(row_idx, note_col, value=note)
        c_note.font = data_font
        c_note.border = thin_border

    ws.column_dimensions['A'].width = 25
    ws.column_dimensions['B'].width = 28
    ws.column_dimensions['C'].width = 20
    ws.column_dimensions['D'].width = 25
    ws.column_dimensions['E'].width = 28
    ws.column_dimensions['F'].width = 18
    for col_letter in ['G', 'H', 'I', 'J', 'K']:
        ws.column_dimensions[col_letter].width = 30
    ws.column_dimensions['L'].width = 32

    # -------------------------------------------------------------
    # Sheet 2: User Default Parameters (SU01 Parameters)
    # -------------------------------------------------------------
    ws_param = wb.create_sheet(title="User Default")

    param_headers = ["Parameter ID", "Parameter Value", "Description"]
    for col_idx, h in enumerate(param_headers, start=1):
        c = ws_param.cell(1, col_idx, value=h)
        c.font = header_font
        c.fill = header_fill
        c.alignment = center_align if col_idx <= 2 else left_align
        c.border = thin_border

    param_defaults = [
        ("CAC", "1000", "Controlling area"),
        ("FIK", "1000", "FM Area"),
        ("ERB", "1000", "Operating Concern"),
        ("EKR", "1000", "Operating Concern"),
        ("IVFIDISPLAY", "X", "Logistics Invoice Verification: Display Accounting Doc. No."),
        ("PFL", "000000000001", "Project information system profile"),
        ("PDB", "000000000001", "Profile for logical database PSJ"),
    ]

    for row_idx, (pid, pva, desc) in enumerate(param_defaults, start=2):
        c_pid = ws_param.cell(row_idx, 1, value=pid)
        c_pid.font = role_name_font
        c_pid.fill = role_name_fill
        c_pid.border = thin_border
        c_pid.alignment = left_align

        c_pva = ws_param.cell(row_idx, 2, value=pva)
        c_pva.font = data_font
        c_pva.border = thin_border
        c_pva.alignment = center_align

        c_desc = ws_param.cell(row_idx, 3, value=desc)
        c_desc.font = data_font
        c_desc.border = thin_border
        c_desc.alignment = left_align

    ws_param.column_dimensions['A'].width = 20
    ws_param.column_dimensions['B'].width = 22
    ws_param.column_dimensions['C'].width = 55

    xlsx_path = os.path.join(OUT_DIR, "Template_User.xlsx")
    wb.save(xlsx_path)
    print(f"[OK] Generated: {xlsx_path}")

    try:
        from convert_user import convert_user_all
        convert_user_all(xlsx_path)
    except ImportError:
        import subprocess
        script_path = os.path.join(os.path.dirname(__file__), "convert_user.py")
        subprocess.run([sys.executable, script_path, xlsx_path], check=True)


# --- CLI Entrypoint ---
if __name__ == "__main__":
    print("\n--- Generating SAP Role & User Templates ---")
    create_consolidated_role_template()
    create_consolidated_user_template()
    print("\n[OK] All consolidated role & user templates and sample converted CSVs generated successfully.")
