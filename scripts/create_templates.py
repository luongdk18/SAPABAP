#!/usr/bin/env python3
"""
Generate standardized, masked template files for SAP Role upload in 'excel-templates/'.
Creates:
1. Template_Roles_Master.xlsx & Template_Roles_Master_converted.csv
2. Template_Roles_Derived.xlsx & Template_Roles_Derived_converted.csv
3. Template_Roles_Derived_Org.xlsx & Template_Roles_Derived_Org_converted.csv
4. Template_Roles_Composite.xlsx & Template_Roles_Composite_converted.csv
5. Template_Users_Create.xlsx & Template_Users_Create_converted.csv

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

# --- Directory & Style Definitions ---
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "excel-templates")
os.makedirs(OUT_DIR, exist_ok=True)

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


# --- 1. Master Roles Template (Template_Roles_Master.xlsx & CSV) ---
def create_master_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Roles_Master_Matrix"

    roles = [
        {"name": "Z_FI_PERIOD_CONTROL", "desc": "GL Period Control", "tcodes": ["OB52", "S_ALR_87003642"]},
        {"name": "Z_FI_GL_MASTER_MAINT", "desc": "GL Master Data Maintenance", "tcodes": ["FS00", "FSP0", "FSS0"]},
        {"name": "Z_FI_JOURNAL_POST", "desc": "General Ledger Journal Posting", "tcodes": ["FB01", "FB02", "FB03", "F-02", "FB50"]},
        {"name": "Z_FI_JOURNAL_DISPLAY", "desc": "General Ledger Journal Display", "tcodes": ["FB03", "FBL3N", "FS10N"]},
        {"name": "Z_FI_AP_INVOICE_PROCESS", "desc": "Accounts Payable Invoice Processing", "tcodes": ["FB60", "FB02", "FB03", "F-53"]},
        {"name": "Z_FI_GL_REPORTS_EMPTY", "desc": "General Ledger Custom Reporting", "tcodes": []}  # Demonstrates N/A role
    ]

    all_tcodes = [
        "OB52", "S_ALR_87003642", "FS00", "FSP0", "FSS0",
        "FB01", "FB02", "FB03", "F-02", "FB50",
        "FBL3N", "FS10N", "FB60", "F-53"
    ]

    # Row 1: Role Description
    ws.cell(1, 1, value="TCode / Role Description").font = header_font
    ws.cell(1, 1).fill = header_fill
    ws.cell(1, 1).alignment = left_align

    # Row 2: Role Name
    ws.cell(2, 1, value="Role Name").font = role_name_font
    ws.cell(2, 1).fill = role_name_fill
    ws.cell(2, 1).alignment = left_align

    for col_idx, r in enumerate(roles, start=2):
        c1 = ws.cell(1, col_idx, value=r["desc"])
        c1.font = header_font
        c1.fill = header_fill
        c1.alignment = left_align

        c2 = ws.cell(2, col_idx, value=r["name"])
        c2.font = role_name_font
        c2.fill = role_name_fill
        c2.alignment = left_align

    # TCode rows (Row 3 onwards)
    flat_rows = []
    for row_idx, tc in enumerate(all_tcodes, start=3):
        c = ws.cell(row_idx, 1, value=tc)
        c.font = data_font
        c.border = thin_border
        for col_idx, r in enumerate(roles, start=2):
            val = "Y" if tc in r["tcodes"] else ""
            cell = ws.cell(row_idx, col_idx, value=val)
            cell.font = data_font
            cell.alignment = center_align
            cell.border = thin_border

    # Build flat rows for CSV
    for r in roles:
        if r["tcodes"]:
            for tc in r["tcodes"]:
                flat_rows.append([r["name"], r["desc"], tc])
        else:
            flat_rows.append([r["name"], r["desc"], "N/A"])

    # Auto-adjust column widths
    ws.column_dimensions['A'].width = 25
    for col_letter in ['B', 'C', 'D', 'E', 'F', 'G']:
        ws.column_dimensions[col_letter].width = 32

    xlsx_path = os.path.join(OUT_DIR, "Template_Roles_Master.xlsx")
    wb.save(xlsx_path)

    csv_path = os.path.join(OUT_DIR, "Template_Roles_Master_converted.csv")
    with open(csv_path, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.writer(f)
        writer.writerow(["Role Name", "Role Description", "TCode"])
        writer.writerows(flat_rows)

    print(f"[OK] Generated: {xlsx_path}")
    print(f"[OK] Generated: {csv_path} ({len(flat_rows)} rows)")


# --- 2. Derived Roles Template (Template_Roles_Derived.xlsx & CSV) ---
def create_derived_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "DERIVED ROLES"

    headers = ["Master Role", "Derived Role", "Derived Role Description"]
    for col_idx, h in enumerate(headers, start=1):
        c = ws.cell(1, col_idx, value=h)
        c.font = header_font
        c.fill = header_fill
        c.alignment = left_align

    derived_rows = [
        ["Z_FI_PERIOD_CONTROL", "Z_FI_PERIOD_CONTROL_1000", "GL Period Control - US Entity 1000"],
        ["Z_FI_PERIOD_CONTROL", "Z_FI_PERIOD_CONTROL_2000", "GL Period Control - EU Entity 2000"],
        ["Z_FI_GL_MASTER_MAINT", "Z_FI_GL_MASTER_MAINT_1000", "GL Master Data Maint - US Entity 1000"],
        ["Z_FI_GL_MASTER_MAINT", "Z_FI_GL_MASTER_MAINT_2000", "GL Master Data Maint - EU Entity 2000"],
        ["Z_FI_JOURNAL_POST", "Z_FI_JOURNAL_POST_1000", "GL Journal Posting - US Entity 1000"],
        ["Z_FI_JOURNAL_POST", "Z_FI_JOURNAL_POST_2000", "GL Journal Posting - EU Entity 2000"],
        ["Z_FI_JOURNAL_DISPLAY", "Z_FI_JOURNAL_DISPLAY_1000", "GL Journal Display - US Entity 1000"],
        ["Z_FI_JOURNAL_DISPLAY", "Z_FI_JOURNAL_DISPLAY_2000", "GL Journal Display - EU Entity 2000"],
        ["Z_FI_AP_INVOICE_PROCESS", "Z_FI_AP_INVOICE_PROCESS_1000", "AP Invoice Processing - US Entity 1000"],
        ["Z_FI_AP_INVOICE_PROCESS", "Z_FI_AP_INVOICE_PROCESS_2000", "AP Invoice Processing - EU Entity 2000"],
        ["Z_FI_GL_REPORTS_EMPTY", "Z_FI_GL_REPORTS_EMPTY_1000", "GL Custom Reporting - US Entity 1000"],
        ["Z_FI_GL_REPORTS_EMPTY", "Z_FI_GL_REPORTS_EMPTY_2000", "GL Custom Reporting - EU Entity 2000"],
    ]

    for row_idx, r in enumerate(derived_rows, start=2):
        for col_idx, val in enumerate(r, start=1):
            c = ws.cell(row_idx, col_idx, value=val)
            c.font = data_font
            c.border = thin_border

    ws.column_dimensions['A'].width = 30
    ws.column_dimensions['B'].width = 32
    ws.column_dimensions['C'].width = 45

    xlsx_path = os.path.join(OUT_DIR, "Template_Roles_Derived.xlsx")
    wb.save(xlsx_path)

    csv_path = os.path.join(OUT_DIR, "Template_Roles_Derived_converted.csv")
    with open(csv_path, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        writer.writerows(derived_rows)

    print(f"[OK] Generated: {xlsx_path}")
    print(f"[OK] Generated: {csv_path} ({len(derived_rows)} rows)")


# --- 3. Derived Roles Org Levels Template (Template_Roles_Derived_Org.xlsx & CSV) ---
def create_org_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "DERIVED ROLES"

    columns = [
        ("Role Name", None),
        ("Operating concern ($CEERKRS)", "$ERKRS"),
        ("Controlling area ($KOKRS)", "$KOKRS"),
        ("Company Code ($BUKRS)", "$BUKRS"),
        ("Plant / Valuation Area", "$WERKS"),
        ("Profit Center", "$PRCTR"),
        ("Cost center", "$KOSTL"),
        ("Business Place", "$BUPLA"),
        ("Segment", "$SEGMENT"),
        ("Purchasing Org ($EKORG)", "$EKORG"),
        ("Sales Org ($VKORG)", "$VKORG")
    ]

    for col_idx, (col_name, _) in enumerate(columns, start=1):
        c = ws.cell(1, col_idx, value=col_name)
        c.font = header_font
        c.fill = header_fill
        c.alignment = left_align

    roles_data = [
        ("Z_FI_PERIOD_CONTROL_1000", "OP01", "1000", "1000", "1000", "PC1000*", "CC1000*", "BP01", "SEG01", "1000", "1000"),
        ("Z_FI_PERIOD_CONTROL_2000", "OP01", "2000", "2000", "2000", "PC2000*", "CC2000*", "BP02", "SEG02", "2000", "2000"),
        ("Z_FI_GL_MASTER_MAINT_1000", "OP01", "1000", "1000", "1000", "PC1000*", "CC1000*", "BP01", "SEG01", "1000", "1000"),
        ("Z_FI_GL_MASTER_MAINT_2000", "OP01", "2000", "2000", "2000", "PC2000*", "CC2000*", "BP02", "SEG02", "2000", "2000"),
        ("Z_FI_JOURNAL_POST_1000", "OP01", "1000", "1000", "1000", "PC1000*", "CC1000*", "BP01", "SEG01", "1000", "1000"),
        ("Z_FI_JOURNAL_POST_2000", "OP01", "2000", "2000", "2000", "PC2000*", "CC2000*", "BP02", "SEG02", "2000", "2000"),
        ("Z_FI_JOURNAL_DISPLAY_1000", "OP01", "1000", "1000", "1000", "PC1000*", "CC1000*", "BP01", "SEG01", "1000", "1000"),
        ("Z_FI_JOURNAL_DISPLAY_2000", "OP01", "2000", "2000", "2000", "PC2000*", "CC2000*", "BP02", "SEG02", "2000", "2000"),
        ("Z_FI_AP_INVOICE_PROCESS_1000", "OP01", "1000", "1000", "1000", "PC1000*", "CC1000*", "BP01", "SEG01", "1000", "1000"),
        ("Z_FI_AP_INVOICE_PROCESS_2000", "OP01", "2000", "2000", "2000", "PC2000*", "CC2000*", "BP02", "SEG02", "2000", "2000"),
        ("Z_FI_GL_REPORTS_EMPTY_1000", "OP01", "1000", "1000", "1000", "PC1000*", "CC1000*", "BP01", "SEG01", "1000", "1000"),
        ("Z_FI_GL_REPORTS_EMPTY_2000", "OP01", "2000", "2000", "2000", "PC2000*", "CC2000*", "BP02", "SEG02", "2000", "2000"),
    ]

    for row_idx, r in enumerate(roles_data, start=2):
        for col_idx, val in enumerate(r, start=1):
            c = ws.cell(row_idx, col_idx, value=val)
            c.font = data_font
            c.border = thin_border

    ws.column_dimensions['A'].width = 32
    for col_letter in ['B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K']:
        ws.column_dimensions[col_letter].width = 28

    xlsx_path = os.path.join(OUT_DIR, "Template_Roles_Derived_Org.xlsx")
    wb.save(xlsx_path)

    # Flat CSV export (Column-major: for each mapped org variable, output rows)
    flat_csv_rows = []
    for col_idx in range(1, len(columns)):
        var = columns[col_idx][1]
        for r in roles_data:
            role_name = r[0]
            val = r[col_idx]
            flat_csv_rows.append([role_name, var, val])

    csv_path = os.path.join(OUT_DIR, "Template_Roles_Derived_Org_converted.csv")
    with open(csv_path, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.writer(f)
        writer.writerow(["Role Name", "Org Level Variable", "Org Value"])
        writer.writerows(flat_csv_rows)

    print(f"[OK] Generated: {xlsx_path}")
    print(f"[OK] Generated: {csv_path} ({len(flat_csv_rows)} rows)")


# --- 4. Composite Roles Template (Template_Roles_Composite.xlsx & CSV) ---
def create_composite_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "COMPOSITE ROLES"

    roles = [
        {
            "name": "Z_FI_COMP_CFO_1000",
            "desc": "Chief Financial Officer - Entity 1000",
            "derived_roles": [
                "Z_FI_PERIOD_CONTROL_1000",
                "Z_FI_GL_MASTER_MAINT_1000",
                "Z_FI_JOURNAL_DISPLAY_1000"
            ]
        },
        {
            "name": "Z_FI_COMP_CFO_2000",
            "desc": "Chief Financial Officer - Entity 2000",
            "derived_roles": [
                "Z_FI_PERIOD_CONTROL_2000",
                "Z_FI_GL_MASTER_MAINT_2000",
                "Z_FI_JOURNAL_DISPLAY_2000"
            ]
        },
        {
            "name": "Z_FI_COMP_ACCOUNTANT_1000",
            "desc": "General Accountant - Entity 1000",
            "derived_roles": [
                "Z_FI_JOURNAL_POST_1000",
                "Z_FI_JOURNAL_DISPLAY_1000",
                "Z_FI_AP_INVOICE_PROCESS_1000"
            ]
        },
        {
            "name": "Z_FI_COMP_ACCOUNTANT_2000",
            "desc": "General Accountant - Entity 2000",
            "derived_roles": [
                "Z_FI_JOURNAL_POST_2000",
                "Z_FI_JOURNAL_DISPLAY_2000",
                "Z_FI_AP_INVOICE_PROCESS_2000"
            ]
        },
        {
            "name": "Z_FI_COMP_CONTROLLER_1000",
            "desc": "Financial Controller - Entity 1000",
            "derived_roles": [
                "Z_FI_PERIOD_CONTROL_1000",
                "Z_FI_JOURNAL_DISPLAY_1000"
            ]
        },
        {
            "name": "Z_FI_COMP_EMPTY_1000",
            "desc": "Empty Composite Role - Entity 1000",
            "derived_roles": []  # Demonstrates N/A fallback row
        }
    ]

    all_derived_roles = [
        "Z_FI_PERIOD_CONTROL_1000",
        "Z_FI_PERIOD_CONTROL_2000",
        "Z_FI_GL_MASTER_MAINT_1000",
        "Z_FI_GL_MASTER_MAINT_2000",
        "Z_FI_JOURNAL_POST_1000",
        "Z_FI_JOURNAL_POST_2000",
        "Z_FI_JOURNAL_DISPLAY_1000",
        "Z_FI_JOURNAL_DISPLAY_2000",
        "Z_FI_AP_INVOICE_PROCESS_1000",
        "Z_FI_AP_INVOICE_PROCESS_2000",
        "Z_FI_GL_REPORTS_EMPTY_1000",
        "Z_FI_GL_REPORTS_EMPTY_2000"
    ]

    # Row 1: Role Description
    ws.cell(1, 1, value="Derived Role / Composite Role Description").font = header_font
    ws.cell(1, 1).fill = header_fill
    ws.cell(1, 1).alignment = left_align

    # Row 2: Role Name
    ws.cell(2, 1, value="Role Name").font = role_name_font
    ws.cell(2, 1).fill = role_name_fill
    ws.cell(2, 1).alignment = left_align

    for col_idx, r in enumerate(roles, start=2):
        c1 = ws.cell(1, col_idx, value=r["desc"])
        c1.font = header_font
        c1.fill = header_fill
        c1.alignment = left_align

        c2 = ws.cell(2, col_idx, value=r["name"])
        c2.font = role_name_font
        c2.fill = role_name_fill
        c2.alignment = left_align

    # Derived Role rows (Row 3 onwards)
    flat_rows = []
    for row_idx, dr in enumerate(all_derived_roles, start=3):
        c = ws.cell(row_idx, 1, value=dr)
        c.font = data_font
        c.border = thin_border
        for col_idx, r in enumerate(roles, start=2):
            val = "Y" if dr in r["derived_roles"] else ""
            cell = ws.cell(row_idx, col_idx, value=val)
            cell.font = data_font
            cell.alignment = center_align
            cell.border = thin_border

    # Build flat rows for CSV in specified column order:
    # Composite role name, composite role description, derived role
    for r in roles:
        if r["derived_roles"]:
            for dr in r["derived_roles"]:
                flat_rows.append([r["name"], r["desc"], dr])
        else:
            flat_rows.append([r["name"], r["desc"], "N/A"])

    # Auto-adjust column widths
    ws.column_dimensions['A'].width = 32
    for col_letter in ['B', 'C', 'D', 'E', 'F', 'G']:
        ws.column_dimensions[col_letter].width = 36

    xlsx_path = os.path.join(OUT_DIR, "Template_Roles_Composite.xlsx")
    wb.save(xlsx_path)

    csv_path = os.path.join(OUT_DIR, "Template_Roles_Composite_converted.csv")
    with open(csv_path, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.writer(f)
        writer.writerow(["Composite Role Name", "Composite Role Description", "Derived Role"])
        writer.writerows(flat_rows)

    print(f"[OK] Generated: {xlsx_path}")
    print(f"[OK] Generated: {csv_path} ({len(flat_rows)} rows)")


# --- 5. Users Creation Template (Template_Users_Create.xlsx & CSV) ---
def create_users_template():
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "User Asignment"

    headers = ["FULL NAME", "Email", "Phone No.", "Department", "Function"]
    for col_idx, h in enumerate(headers, start=1):
        c = ws.cell(1, col_idx, value=h)
        c.font = header_font
        c.fill = header_fill
        c.alignment = left_align

    sample_users = [
        ["John Doe", "johnd@company.com", "+84 981 234 567", "Finance & Accounting", "Finance Controller"],
        ["Jane Smith", "janes@company.com", "+84 971 888 999", "Finance & Accounting", "Senior Accountant"],
        ["Alex Johnson", "alexj@company.com", "+996 555 123 456", "PMU", "Project Director"],
        ["Michael Brown", "michaelb@company.com", "+996 500 654 321", "PMU", "Civil Engineer"],
        ["Emily Davis", "emilyd", None, "Administration", "HR Specialist"],
        ["David Wilson", "davidw@company.com", "0987654321", "operation", "OM"],
    ]

    for row_idx, r in enumerate(sample_users, start=2):
        for col_idx, val in enumerate(r, start=1):
            c = ws.cell(row_idx, col_idx, value=val)
            c.font = data_font
            c.border = thin_border

    ws.column_dimensions['A'].width = 28
    ws.column_dimensions['B'].width = 30
    ws.column_dimensions['C'].width = 22
    ws.column_dimensions['D'].width = 25
    ws.column_dimensions['E'].width = 30

    xlsx_path = os.path.join(OUT_DIR, "Template_Users_Create.xlsx")
    wb.save(xlsx_path)
    print(f"[OK] Generated: {xlsx_path}")

    # Convert using convert_users_excel
    try:
        from convert_users_excel import convert_users_excel
        convert_users_excel(xlsx_path)
    except ImportError:
        import subprocess
        script_path = os.path.join(os.path.dirname(__file__), "convert_users_excel.py")
        subprocess.run([sys.executable, script_path, xlsx_path], check=True)


# --- CLI Entrypoint ---
if __name__ == "__main__":
    print("\n--- Generating SAP Role & User Templates ---")
    create_master_template()
    create_derived_template()
    create_org_template()
    create_composite_template()
    create_users_template()
    print("\n[OK] All role & user templates and sample converted CSVs generated successfully.")
