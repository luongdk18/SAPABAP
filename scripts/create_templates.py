#!/usr/bin/env python3
"""
Generate comprehensive, standardized, sanitized template files and edge-case test scenarios
for SAP Role and User batch upload in 'excel-templates/'.

Generated Files:
1. Template_Role.xlsx (Consolidated 3-sheet Multi-Module Role Workbook: FI, FI-AA, CO, MM, SD, PS)
   - Sheet 1: Master Roles (14 Master Roles across FI, FI-AA, CO, MM, SD, PS + Empty Menu role)
   - Sheet 2: Derived Roles & Org/Object/Activity Data (27 Derived Roles across CC 1000/2000/3000)
   - Sheet 3: Composite Roles (10 Composite Roles aligned with Sheet 2 + Empty Composite role)
   -> Auto-converts to:
      * excel-templates/converted/Template_Role_01_Master_converted.csv
      * excel-templates/converted/Template_Role_02_Derived_converted.csv
      * excel-templates/converted/Template_Role_03a_Org_Levels_converted.csv
      * excel-templates/converted/Template_Role_03b_Auth_Objects_converted.csv
      * excel-templates/converted/Template_Role_03c_Activity_converted.csv
      * excel-templates/converted/Template_Role_04_Composite_converted.csv

2. Template_User.xlsx (Consolidated User & Role Assignment Matrix)
   - Sheet 1: User Asignment (16 diverse users: EN & Vietnamese UTF-8 names, explicit/auto passwords,
              invalid email, anti-spam note, multi-role & empty-role users)
   - Sheet 2: User Default (10 Default SU01 Parameters filling all 10 screen slots)
   -> Auto-converts to:
      * excel-templates/converted/Template_User_01_Create_converted.csv
      * excel-templates/converted/Template_User_02_Assign_converted.csv
      * excel-templates/converted/Template_User_Create_Parameter_converted.csv

3. excel-templates/test-scenarios/ (Round-2 Delta, Sync vs Append & Negative/Edge-Case Test Pack)
   - Delta_Role_01_Master_converted.csv
   - Delta_Role_02_Derived_converted.csv
   - Delta_Role_03a_Org_Levels_converted.csv
   - Delta_Role_03b_Auth_Objects_converted.csv
   - Delta_Role_03c_Activity_converted.csv
   - Delta_Role_04_Composite_converted.csv
   - Delta_User_01_Create_converted.csv
   - Delta_User_02_Assign_converted.csv
   - README_TEST_SCENARIOS.md

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
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(REPO_ROOT, "excel-templates")
CONVERTED_DIR = os.path.join(OUT_DIR, "converted")
SCENARIOS_DIR = os.path.join(OUT_DIR, "test-scenarios")
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(CONVERTED_DIR, exist_ok=True)
os.makedirs(SCENARIOS_DIR, exist_ok=True)

header_fill = PatternFill(start_color="1F497D", end_color="1F497D", fill_type="solid")
header_font = Font(name="Calibri", size=11, bold=True, color="FFFFFF")
role_name_fill = PatternFill(start_color="DCE6F1", end_color="DCE6F1", fill_type="solid")
role_name_font = Font(name="Calibri", size=11, bold=True, color="000000")
data_font = Font(name="Calibri", size=11)
center_align = Alignment(horizontal="center", vertical="center", wrap_text=True)
left_align = Alignment(horizontal="left", vertical="center")
thin_border = Border(
    left=Side(style='thin', color='D9D9D9'),
    right=Side(style='thin', color='D9D9D9'),
    top=Side(style='thin', color='D9D9D9'),
    bottom=Side(style='thin', color='D9D9D9')
)


def _sanitize_workbook_props(wb):
    """Ensure workbook metadata never contains local OS usernames."""
    wb.properties.creator = "Template"
    wb.properties.lastModifiedBy = "Template"


def _assert_role_len(role_name):
    if role_name and len(role_name) > 30:
        raise ValueError(f"Role name exceeds SAP 30-char limit ({len(role_name)}): {role_name}")


# --- 1. Consolidated Multi-Module Role Template (Template_Role.xlsx) ---
def create_consolidated_role_template():
    wb = openpyxl.Workbook()
    _sanitize_workbook_props(wb)

    # -------------------------------------------------------------
    # Sheet 1: Master Roles (14 roles across FI, FI-AA, CO, MM, SD, PS)
    # -------------------------------------------------------------
    ws1 = wb.active
    ws1.title = "Master"

    roles = [
        {"name": "Z_FI_PERIOD_CONTROL",   "desc": "FI GL Period Control",             "tcodes": ["OB52", "S_ALR_87003642"]},
        {"name": "Z_FI_GL_MASTER_MAINT",  "desc": "FI GL Master Data Maintenance",    "tcodes": ["FS00", "FSP0", "FSS0"]},
        {"name": "Z_FI_JOURNAL_POST",     "desc": "FI General Ledger Posting",        "tcodes": ["FB01", "FB02", "FB03", "F-02", "FB50"]},
        {"name": "Z_FI_JOURNAL_DISPLAY",  "desc": "FI General Ledger Display",        "tcodes": ["FB03", "FBL3N", "FS10N"]},
        {"name": "Z_FI_AP_INVOICE_PROC",  "desc": "FI AP Invoice & Payment",          "tcodes": ["FB60", "FB65", "FB02", "FB03", "FBL1N", "F-53"]},
        {"name": "Z_FI_AR_INVOICE_PROC",  "desc": "FI AR Billing & Customer Clear",   "tcodes": ["FB70", "FB75", "FBL5N", "F-28", "FD32"]},
        {"name": "Z_FI_ASSET_ACCOUNTING", "desc": "FI-AA Fixed Asset Accounting",     "tcodes": ["AS01", "AS02", "AS03", "AW01N", "AFAB"]},
        {"name": "Z_CO_COST_CENTER",      "desc": "CO Cost Center & Internal Orders", "tcodes": ["KS01", "KS02", "KS03", "KSB1", "KO01", "KO03", "KOB1"]},
        {"name": "Z_MM_PR_PROCESSING",    "desc": "MM Purchase Requisition Mgmt",     "tcodes": ["ME51N", "ME52N", "ME53N", "ME54N", "ME5A"]},
        {"name": "Z_MM_PO_PROCESSING",    "desc": "MM Purchase Order & Release",      "tcodes": ["ME21N", "ME22N", "ME23N", "ME29N", "ME2N"]},
        {"name": "Z_MM_INVENTORY_MGMT",   "desc": "MM Goods Movement & LIV",          "tcodes": ["MIGO", "MB51", "MB52", "MMBE", "MIRO", "MIR4"]},
        {"name": "Z_SD_ORDER_BILLING",    "desc": "SD Sales Order & Billing",         "tcodes": ["VA01", "VA02", "VA03", "VL01N", "VF01", "VF03"]},
        {"name": "Z_PS_PROJECT_MGMT",     "desc": "PS Project Builder & Reports",     "tcodes": ["CJ20N", "CJ03", "CN41N", "CJI3"]},
        {"name": "Z_FI_GL_REPORTS_EMPTY", "desc": "FI Custom Reporting (Empty Menu)", "tcodes": []},
    ]

    for r in roles:
        _assert_role_len(r["name"])

    all_tcodes = sorted({tc for r in roles for tc in r["tcodes"]})
    c_hdr = ws1.cell(1, 1, value="TCode / Role")
    c_hdr.font = header_font
    c_hdr.fill = header_fill
    c_hdr.border = thin_border

    for col_idx, r in enumerate(roles, start=2):
        c_desc = ws1.cell(1, col_idx, value=r["desc"])
        c_desc.font = header_font
        c_desc.fill = header_fill
        c_desc.alignment = center_align
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

    ws1.column_dimensions['A'].width = 20
    for col_idx in range(2, len(roles) + 2):
        ws1.column_dimensions[openpyxl.utils.get_column_letter(col_idx)].width = 28

    # -------------------------------------------------------------
    # Sheet 2: Derived Roles & Org + Object + Activity Levels
    # -------------------------------------------------------------
    ws2 = wb.create_sheet(title="Derived")

    headers_s2 = [
        None, None, None,
        "ACTVT, PS_ACTVT",
        "Operating concern\n($CEERKRS)",
        "Controlling area\n($KOKRS)",
        "Company Code ($BUKRS)",
        "Plant / Valuation Area",
        "Purchasing Organization\n($EKORG)",
        "Purchasing Group\n($EKGRP)",
        "Sales Organization\n($VKORG)",
        "Distribution Channel\n($VTWEG)",
        "Division ($SPART)",
        "Profit Center (C_PROJ_PRC, C_PRPS_PRC)",
        "Cost center",
        "Storage Location",
        "Release Group",
        "Release Code",
        "Order type",
        "Asset Class",
        "Segment",
        "Business Place",
        "Credit segment",
        "Costing variant (K_KEKO)",
        "Person Responsible (C_PROJ_VNR-PS_VERNR, C_PRPS_VNR-PS_VERNR)",
    ]

    for col_idx, h in enumerate(headers_s2, start=1):
        if h:
            c = ws2.cell(1, col_idx, value=h)
            c.font = header_font
            c.fill = header_fill
            c.alignment = center_align
            c.border = thin_border

    # Helper to construct a 25-column row cleanly
    def row(master, derived, desc, actvt=None,
            ceerkrs=None, kokrs=None, bukrs=None, werks=None,
            ekorg=None, ekgrp=None, vkorg=None, vtweg=None, spart=None,
            prctr=None, kostl=None, lgort=None, frggr=None, frgco=None,
            aufart=None, anlkl=None, segment=None, bupla=None, credit=None,
            klvar=None, vernr=None):
        _assert_role_len(master)
        _assert_role_len(derived)
        return (
            master, derived, desc, actvt,
            ceerkrs, kokrs, bukrs, werks,
            ekorg, ekgrp, vkorg, vtweg, spart,
            prctr, kostl, lgort, frggr, frgco,
            aufart, anlkl, segment, bupla, credit,
            klvar, vernr
        )

    derived_rows = [
        # --- FI Period Control (CC 1000, 2000) ---
        row("Z_FI_PERIOD_CONTROL", "Z_FI_PERIOD_CONTROL_1000", "FI GL Period Control - CC 1000",
            actvt="*", ceerkrs="1000", kokrs="1000", bukrs="1000", werks="1000",
            prctr="10000100 - 10009899; ' '", kostl="1000*", aufart="*", anlkl="*",
            segment="1000_SEG", bupla="1000", credit="*", klvar="*", vernr="00000000; 00000080"),
        row("Z_FI_PERIOD_CONTROL", "Z_FI_PERIOD_CONTROL_2000", "FI GL Period Control - CC 2000",
            actvt="03, F4", ceerkrs="1000", kokrs="1000", bukrs="2000", werks="2000",
            prctr="' '", kostl="2000*", aufart="*", anlkl="*",
            segment="2000_SEG", bupla="2000", credit="*", klvar="*", vernr="*"),

        # --- FI GL Master Data Maint (CC 1000 with multi-row continuation, CC 2000) ---
        row("Z_FI_GL_MASTER_MAINT", "Z_FI_GL_MASTER_MAINT_1000", "FI GL Master Maint - CC 1000",
            actvt="01, 02, 03", ceerkrs="1000", kokrs="1000", bukrs="1000", werks="1000",
            prctr="10009930; ' '", kostl="1000*", segment="1000_SEG", bupla="1000", vernr="00000000;"),
        row(None, None, None, kostl="10001000 - 10001999", vernr=30),
        row("Z_FI_GL_MASTER_MAINT", "Z_FI_GL_MASTER_MAINT_2000", "FI GL Master Maint - CC 2000",
            actvt="03, F4", ceerkrs="1000", kokrs="1000", bukrs="2000", werks="2000",
            prctr="20000100 - 20009899; ' '", kostl="2000*", segment="2000_SEG", bupla="2000", vernr="*"),

        # --- FI Journal Posting (CC 1000, 2000, 3000 multi-CC test) ---
        row("Z_FI_JOURNAL_POST", "Z_FI_JOURNAL_POST_1000", "FI GL Journal Post - CC 1000",
            actvt="01, 02, 03, 77", ceerkrs="1000", kokrs="1000", bukrs="1000", werks="1000",
            prctr="1000*", kostl="1000*", segment="1000_SEG", bupla="1000"),
        row("Z_FI_JOURNAL_POST", "Z_FI_JOURNAL_POST_2000", "FI GL Journal Post - CC 2000",
            actvt="01, 02, 03", ceerkrs="1000", kokrs="1000", bukrs="2000", werks="2000",
            prctr="2000*", kostl="2000*", segment="2000_SEG", bupla="2000"),
        row("Z_FI_JOURNAL_POST", "Z_FI_JOURNAL_POST_ALL", "FI GL Journal Post - Multi CC",
            actvt="01, 02, 03", ceerkrs="1000", kokrs="1000", bukrs="1000; 2000; 3000",
            prctr="*", kostl="*", segment="*"),

        # --- FI Journal Display (Read-Only CC 1000, 2000) ---
        row("Z_FI_JOURNAL_DISPLAY", "Z_FI_JOURNAL_DISP_1000", "FI GL Journal Display - CC 1000",
            actvt="03, F4", kokrs="1000", bukrs="1000", prctr="1000*", segment="1000_SEG"),
        row("Z_FI_JOURNAL_DISPLAY", "Z_FI_JOURNAL_DISP_2000", "FI GL Journal Display - CC 2000",
            actvt="03, F4", kokrs="1000", bukrs="2000", prctr="2000*", segment="2000_SEG"),

        # --- FI AP Invoice Processing (CC 1000, 2000) ---
        row("Z_FI_AP_INVOICE_PROC", "Z_FI_AP_INVOICE_1000", "FI AP Invoice Process - CC 1000",
            actvt="01, 02, 03", kokrs="1000", bukrs="1000", werks="1000",
            prctr="1000*", kostl="1000*", bupla="1000"),
        row("Z_FI_AP_INVOICE_PROC", "Z_FI_AP_INVOICE_2000", "FI AP Invoice Process - CC 2000",
            actvt="01, 02, 03", kokrs="1000", bukrs="2000", werks="2000",
            prctr="2000*", kostl="2000*", bupla="2000"),

        # --- FI AR Invoice & Credit Mgmt (CC 1000, 2000) ---
        row("Z_FI_AR_INVOICE_PROC", "Z_FI_AR_INVOICE_1000", "FI AR Billing & Credit - CC 1000",
            actvt="01, 02, 03", kokrs="1000", bukrs="1000",
            prctr="1000*", bupla="1000", credit="1000_CR; 1001_CR"),
        row("Z_FI_AR_INVOICE_PROC", "Z_FI_AR_INVOICE_2000", "FI AR Billing & Credit - CC 2000",
            actvt="03", kokrs="1000", bukrs="2000",
            prctr="2000*", bupla="2000", credit="2000_CR"),

        # --- FI-AA Fixed Asset Accounting (CC 1000, 2000) ---
        row("Z_FI_ASSET_ACCOUNTING", "Z_FI_ASSET_1000", "FI-AA Fixed Assets - CC 1000",
            actvt="01, 02, 03, 05", kokrs="1000", bukrs="1000", werks="1000",
            kostl="1000*", anlkl="1000 - 3999"),
        row("Z_FI_ASSET_ACCOUNTING", "Z_FI_ASSET_2000", "FI-AA Fixed Assets - CC 2000",
            actvt="03", kokrs="1000", bukrs="2000", werks="2000",
            kostl="2000*", anlkl="1000; 2000"),

        # --- CO Cost Center & Internal Orders (CC 1000, 2000) ---
        row("Z_CO_COST_CENTER", "Z_CO_COST_CENTER_1000", "CO Cost Center & Order - CC 1000",
            actvt="01, 02, 03", ceerkrs="1000", kokrs="1000", bukrs="1000",
            prctr="1000*", kostl="10000010 - 10000999", aufart="0100; 0400", klvar="PPC1; ZPC1"),
        row("Z_CO_COST_CENTER", "Z_CO_COST_CENTER_2000", "CO Cost Center & Order - CC 2000",
            actvt="03", ceerkrs="1000", kokrs="1000", bukrs="2000",
            prctr="2000*", kostl="2000*", aufart="0100", klvar="PPC1"),

        # --- MM Purchase Requisition (Plant 1000, 2000) ---
        row("Z_MM_PR_PROCESSING", "Z_MM_PR_1000", "MM Purchase Req - Plant 1000",
            actvt="01, 02, 03", bukrs="1000", werks="1000", ekorg="1000", ekgrp="001; 002",
            lgort="0001; 0002", frggr="01", frgco="R1"),
        row("Z_MM_PR_PROCESSING", "Z_MM_PR_2000", "MM Purchase Req - Plant 2000",
            actvt="01, 02, 03", bukrs="2000", werks="2000", ekorg="2000", ekgrp="003",
            lgort="0001", frggr="02", frgco="R2"),

        # --- MM Purchase Order & Release (Plant 1000, 2000) ---
        row("Z_MM_PO_PROCESSING", "Z_MM_PO_1000", "MM Purchase Order - Plant 1000",
            actvt="01, 02, 03, 09", bukrs="1000", werks="1000", ekorg="1000", ekgrp="001; 002",
            lgort="0001; 0002", frggr="01", frgco="R1; R2"),
        row("Z_MM_PO_PROCESSING", "Z_MM_PO_2000", "MM Purchase Order - Plant 2000",
            actvt="01, 02, 03", bukrs="2000", werks="2000", ekorg="2000", ekgrp="003",
            lgort="0001", frggr="02", frgco="R2"),

        # --- MM Inventory Management & LIV (Plant 1000, 2000) ---
        row("Z_MM_INVENTORY_MGMT", "Z_MM_INVENTORY_1000", "MM Goods Movement - Plant 1000",
            actvt="01, 02, 03", bukrs="1000", werks="1000", ekorg="1000",
            lgort="0001; 0002; 0003"),
        row("Z_MM_INVENTORY_MGMT", "Z_MM_INVENTORY_2000", "MM Goods Movement - Plant 2000",
            actvt="01, 03", bukrs="2000", werks="2000", ekorg="2000",
            lgort="0001"),

        # --- SD Sales Order & Billing (SO 1000, 2000) ---
        row("Z_SD_ORDER_BILLING", "Z_SD_SALES_1000", "SD Sales & Billing - SO 1000",
            actvt="01, 02, 03", bukrs="1000", werks="1000",
            vkorg="1000", vtweg="10; 20", spart="00; 01", prctr="1000*"),
        row("Z_SD_ORDER_BILLING", "Z_SD_SALES_2000", "SD Sales & Billing - SO 2000",
            actvt="03", bukrs="2000", werks="2000",
            vkorg="2000", vtweg="10", spart="00", prctr="2000*"),

        # --- PS Project Builder & Reporting (CC 1000, 2000 — tests PS_ACTVT + PS_VERNR NUMC 8) ---
        row("Z_PS_PROJECT_MGMT", "Z_PS_PROJECT_1000", "PS Project Mgmt - CC 1000",
            actvt="01, 02, 03", kokrs="1000", bukrs="1000", werks="1000",
            prctr="10000100 - 10009899", kostl="1000*", vernr="10; 30; 80"),
        row("Z_PS_PROJECT_MGMT", "Z_PS_PROJECT_2000", "PS Project Mgmt - CC 2000",
            actvt="03", kokrs="1000", bukrs="2000", werks="2000",
            prctr="2000*", kostl="2000*", vernr="20"),
    ]

    for row_idx, r_data in enumerate(derived_rows, start=2):
        for col_idx, val in enumerate(r_data, start=1):
            c = ws2.cell(row_idx, col_idx, value=val)
            if col_idx in (1, 2) and val:
                c.font = role_name_font
                c.fill = role_name_fill
            else:
                c.font = data_font
                if col_idx > 3 and val is not None:
                    c.alignment = center_align
            c.border = thin_border

    ws2.column_dimensions['A'].width = 26
    ws2.column_dimensions['B'].width = 28
    ws2.column_dimensions['C'].width = 34
    for col_idx in range(4, len(headers_s2) + 1):
        ws2.column_dimensions[openpyxl.utils.get_column_letter(col_idx)].width = 24

    # -------------------------------------------------------------
    # Sheet 3: Composite Roles (10 Composite Roles matching Sheet 2)
    # -------------------------------------------------------------
    ws3 = wb.create_sheet(title="Composite")

    comp_roles = [
        {
            "name": "Z_FI_COMP_CFO_1000",
            "desc": "Chief Financial Officer - CC 1000",
            "singles": [
                "Z_FI_PERIOD_CONTROL_1000",
                "Z_FI_JOURNAL_POST_1000",
                "Z_FI_JOURNAL_DISP_1000",
                "Z_CO_COST_CENTER_1000",
            ],
        },
        {
            "name": "Z_FI_COMP_ACCOUNTANT_1000",
            "desc": "GL & AP/AR Accountant - CC 1000",
            "singles": [
                "Z_FI_GL_MASTER_MAINT_1000",
                "Z_FI_JOURNAL_POST_1000",
                "Z_FI_AP_INVOICE_1000",
                "Z_FI_AR_INVOICE_1000",
                "Z_FI_ASSET_1000",
            ],
        },
        {
            "name": "Z_FI_COMP_CONTROLLER_1000",
            "desc": "Financial Controller - CC 1000",
            "singles": [
                "Z_FI_PERIOD_CONTROL_1000",
                "Z_FI_GL_MASTER_MAINT_1000",
                "Z_CO_COST_CENTER_1000",
            ],
        },
        {
            "name": "Z_FI_COMP_ACCOUNTANT_2000",
            "desc": "GL & AP Accountant - CC 2000",
            "singles": [
                "Z_FI_GL_MASTER_MAINT_2000",
                "Z_FI_JOURNAL_POST_2000",
                "Z_FI_AP_INVOICE_2000",
                "Z_FI_ASSET_2000",
            ],
        },
        {
            "name": "Z_FI_COMP_AUDITOR_RO",
            "desc": "Read-Only Auditor - CC 1000/2000",
            "singles": [
                "Z_FI_JOURNAL_DISP_1000",
                "Z_FI_JOURNAL_DISP_2000",
                "Z_CO_COST_CENTER_2000",
                "Z_FI_AR_INVOICE_2000",
            ],
        },
        {
            "name": "Z_MM_COMP_PURCHASER_1000",
            "desc": "Purchasing Specialist - Plant 1000",
            "singles": [
                "Z_MM_PR_1000",
                "Z_MM_PO_1000",
            ],
        },
        {
            "name": "Z_MM_COMP_WAREHOUSE_1000",
            "desc": "Warehouse & GR Clerk - Plant 1000",
            "singles": [
                "Z_MM_PR_1000",
                "Z_MM_INVENTORY_1000",
            ],
        },
        {
            "name": "Z_SD_COMP_SALES_1000",
            "desc": "Sales & Billing Spec - SO 1000",
            "singles": [
                "Z_SD_SALES_1000",
                "Z_FI_AR_INVOICE_1000",
            ],
        },
        {
            "name": "Z_PS_COMP_PM_1000",
            "desc": "Project Manager - CC 1000",
            "singles": [
                "Z_PS_PROJECT_1000",
                "Z_CO_COST_CENTER_1000",
                "Z_MM_PR_1000",
            ],
        },
        {
            "name": "Z_COMP_EMPTY_TEST",
            "desc": "Empty Composite Role (Test)",
            "singles": [],
        },
    ]

    for cr in comp_roles:
        _assert_role_len(cr["name"])

    all_singles = sorted({s for cr in comp_roles for s in cr["singles"]})

    c_hdr3 = ws3.cell(1, 1, value="Single Role / Composite")
    c_hdr3.font = header_font
    c_hdr3.fill = header_fill
    c_hdr3.border = thin_border

    for col_idx, cr in enumerate(comp_roles, start=2):
        c_desc = ws3.cell(1, col_idx, value=cr["desc"])
        c_desc.font = header_font
        c_desc.fill = header_fill
        c_desc.alignment = center_align
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

    ws3.column_dimensions['A'].width = 30
    for col_idx in range(2, len(comp_roles) + 2):
        ws3.column_dimensions[openpyxl.utils.get_column_letter(col_idx)].width = 30

    xlsx_path = os.path.join(OUT_DIR, "Template_Role.xlsx")
    wb.save(xlsx_path)
    print(f"[OK] Generated consolidated role template: {xlsx_path}")

    # Auto-convert to all 6 converted CSV files
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
    _sanitize_workbook_props(wb)
    ws = wb.active
    ws.title = "User Asignment"

    user_info_headers = ["FULL NAME", "Email", "Phone No.", "Department", "Function", "Initial Password"]
    roles = [
        "CR_COMMON",
        "Z_FI_COMP_CFO_1000",
        "Z_FI_COMP_ACCOUNTANT_1000",
        "Z_FI_COMP_CONTROLLER_1000",
        "Z_FI_COMP_ACCOUNTANT_2000",
        "Z_FI_COMP_AUDITOR_RO",
        "Z_MM_COMP_PURCHASER_1000",
        "Z_MM_COMP_WAREHOUSE_1000",
        "Z_SD_COMP_SALES_1000",
        "Z_PS_COMP_PM_1000",
        "Z_MM_PO_2000",
        "Z_SD_SALES_2000",
    ]
    all_headers = user_info_headers + roles + ["Note"]

    for col_idx, h in enumerate(all_headers, start=1):
        c = ws.cell(1, col_idx, value=h)
        c.font = header_font
        c.fill = header_fill
        c.alignment = center_align if (len(user_info_headers) < col_idx <= len(user_info_headers) + len(roles)) else left_align
        c.border = thin_border

    # Format: [Name, Email, Phone, Dept, Func, Pwd, [Assigned Roles], Note]
    # 100% generic/synthetic personas with RFC 2606 @example.com emails
    consolidated_users = [
        ["John Doe",        "johnd@example.com",      "+84 999 999 999", "Finance & Accounting", "Chief Financial Officer", "InitPass@2026",
         ["CR_COMMON", "Z_FI_COMP_CFO_1000"], None],
        ["Jane Smith",      "JaneS@Example.com",      "0999999999",      "Finance & Accounting", "Senior Accountant",       None,
         ["CR_COMMON", "Z_FI_COMP_ACCOUNTANT_1000"], None],
        ["Alex Johnson",    "alexj@example.com",      "+1 999 999 9999", "Controlling",          "Financial Controller",    "Alex#2026Secure",
         ["CR_COMMON", "Z_FI_COMP_CONTROLLER_1000"], None],
        ["Michael Brown",   "michaelb@example.com",   "+84 999 999 999", "Procurement",          "Purchasing Manager",      None,
         ["CR_COMMON", "Z_MM_COMP_PURCHASER_1000", "Z_MM_PO_2000"], "Không gán mail gốc tránh spam"],
        ["Emily Davis",     "emilyd",                 None,              "Administration",       "HR Specialist",           None,
         ["CR_COMMON"], "Invalid email syntax test"],
        ["David Wilson",    "davidw@example.com",     "0999999999",      "Warehouse Operations", "Warehouse Lead",          "DavidW!2026",
         ["CR_COMMON", "Z_MM_COMP_WAREHOUSE_1000"], None],
        ["Sarah Miller",    "sarahm@example.com",     "+84 999 999 001", "Sales & Distribution", "Sales Executive",         None,
         ["CR_COMMON", "Z_SD_COMP_SALES_1000", "Z_SD_SALES_2000"], None],
        ["Robert Taylor",   "robertt@example.com",    "+84 999 999 002", "PMU",                  "Project Director",        "RobT@2026Pwd",
         ["CR_COMMON", "Z_PS_COMP_PM_1000"], None],
        ["Lisa Anderson",   "lisaa@example.com",      "+84 999 999 003", "Internal Audit",       "Senior Auditor",          None,
         ["CR_COMMON", "Z_FI_COMP_AUDITOR_RO"], None],
        ["Thomas White",    "thomasw@example.com",    "+84 999 999 004", "Finance & Accounting", "Branch Accountant",       "ThomW#2026",
         ["CR_COMMON", "Z_FI_COMP_ACCOUNTANT_2000"], None],
        ["Anna Clark",      "annac@example.com",      "+84 999 999 005", "Procurement",          "Senior Buyer",            None,
         ["CR_COMMON", "Z_MM_COMP_PURCHASER_1000"], None],
        ["Chris Martin",    "chrism@example.com",     "+84 999 999 006", "Sales & Distribution", "Billing Specialist",      None,
         ["CR_COMMON", "Z_SD_COMP_SALES_1000"], None],
        # Vietnamese UTF-8 accented generic synthetic test personas
        ["Nguyễn Văn A",    "user_vn01@example.com",  "+84 999 999 101", "Kế toán",              "Kế toán trưởng",          "VietA@2026Pass",
         ["CR_COMMON", "Z_FI_COMP_CFO_1000", "Z_FI_COMP_ACCOUNTANT_1000"], None],
        ["Trần Thị B",      "user_vn02@example.com",  "0999999102",      "Mua hàng",             "Chuyên viên Mua hàng",    None,
         ["CR_COMMON", "Z_MM_COMP_PURCHASER_1000"], None],
        ["Lê Văn C",        "user_vn03@example.com",  "0999999103",      "Kinh doanh",           "Trưởng phòng Kinh doanh", None,
         ["CR_COMMON", "Z_SD_COMP_SALES_1000", "Z_FI_COMP_AUDITOR_RO"], None],
        # Empty-roles boundary test user
        ["Empty User",      "empty_user@example.com", None,              "Testing",              "QA Tester",               None,
         [], "Zero roles assigned test"],
    ]

    for row_idx, u in enumerate(consolidated_users, start=2):
        name, email, phone, dept, func, pwd, assigned_roles, note = u
        row_vals = [name, email, phone, dept, func, pwd]
        for col_idx, val in enumerate(row_vals, start=1):
            c = ws.cell(row_idx, col_idx, value=val)
            c.font = data_font
            c.border = thin_border

        start_role_col = len(user_info_headers) + 1
        for r_offset, rname in enumerate(roles):
            c_idx = start_role_col + r_offset
            c_val = "X" if rname in assigned_roles else ""
            c = ws.cell(row_idx, c_idx, value=c_val)
            c.font = data_font
            c.alignment = center_align
            c.border = thin_border

        note_col = len(all_headers)
        c_note = ws.cell(row_idx, note_col, value=note)
        c_note.font = data_font
        c_note.border = thin_border

    col_widths = [24, 28, 18, 24, 28, 18] + [28] * len(roles) + [34]
    for col_idx, w in enumerate(col_widths, start=1):
        ws.column_dimensions[openpyxl.utils.get_column_letter(col_idx)].width = w

    # -------------------------------------------------------------
    # Sheet 2: User Default Parameters (all 10 SU01 Parameter slots)
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
        ("CAC",         "1000",         "Controlling Area"),
        ("BUK",         "1000",         "Company Code"),
        ("FIK",         "1000",         "Financial Management Area"),
        ("ERB",         "1000",         "Operating Concern"),
        ("EKR",         "1000",         "Operating Concern (CO-PA)"),
        ("WRK",         "1000",         "Default Plant"),
        ("EKO",         "1000",         "Purchasing Organization"),
        ("IVFIDISPLAY", "X",            "LIV: Display Accounting Document Number"),
        ("PFL",         "000000000001", "Project Information System Profile"),
        ("PDB",         "000000000001", "Profile for Logical Database PSJ"),
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
    ws_param.column_dimensions['C'].width = 50

    xlsx_path = os.path.join(OUT_DIR, "Template_User.xlsx")
    wb.save(xlsx_path)
    print(f"[OK] Generated consolidated user template: {xlsx_path}")

    try:
        from convert_user import convert_user_all
        convert_user_all(xlsx_path)
    except ImportError:
        import subprocess
        script_path = os.path.join(SCRIPT_DIR, "convert_user.py")
        subprocess.run([sys.executable, script_path, xlsx_path], check=True)


# --- 3. Round-2 Delta & Edge-Case Test Pack (excel-templates/test-scenarios/) ---
def _write_csv(path, header, rows):
    with open(path, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)
    print(f"[OK] Generated scenario CSV: {path} ({len(rows)} rows)")


def create_delta_test_scenarios():
    """
    Generates ready-to-upload Round-2 CSVs specifically crafted to test:
    - Two-Way Sync vs Append Only on every Role & User maintenance report
    - Validation guards (>30-char role names, >12-char usernames, invalid TCodes/emails,
      blocked Org fields in 03b/03c, nested composite roles, missing roles/users)
    - Stale password non-bleed, ALPHA zero-padding, RFC 4180 quoted commas, duplicate period cleanup
    """

    # 1. Master Role Delta (Z_ROLE_01_CREATE_MASTER)
    _write_csv(
        os.path.join(SCENARIOS_DIR, "Delta_Role_01_Master_converted.csv"),
        ["Role Name", "Role Description", "TCode"],
        [
            # Existing role: add FB65, omit F-02 (Sync removes F-02; Append keeps F-02 + adds FB65)
            ["Z_FI_JOURNAL_POST", "FI General Ledger Posting (Updated)", "FB01"],
            ["Z_FI_JOURNAL_POST", "FI General Ledger Posting (Updated)", "FB02"],
            ["Z_FI_JOURNAL_POST", "FI General Ledger Posting (Updated)", "FB03"],
            ["Z_FI_JOURNAL_POST", "FI General Ledger Posting (Updated)", "FB50"],
            ["Z_FI_JOURNAL_POST", "FI General Ledger Posting (Updated)", "FB65"],
            # Existing role with an invalid TCode to test TSTC validation warning
            ["Z_FI_PERIOD_CONTROL", "FI GL Period Control", "OB52"],
            ["Z_FI_PERIOD_CONTROL", "FI GL Period Control", "S_ALR_87003642"],
            ["Z_FI_PERIOD_CONTROL", "FI GL Period Control", "Z_INVALID_TCODE_99"],
            # Negative test: existing Composite Role (must be blocked from Master overwrite)
            ["Z_FI_COMP_CFO_1000", "Should Be Rejected", "FB03"],
            # Negative test: >30-char role name (must be rejected cleanly without truncation)
            ["Z_ROLE_NAME_EXCEEDS_THIRTY_CHARS_01", "Oversized Role Name Test", "FB03"],
        ],
    )

    # 2. Derived Role Delta (Z_ROLE_02_CREATE_DERIVE)
    _write_csv(
        os.path.join(SCENARIOS_DIR, "Delta_Role_02_Derived_converted.csv"),
        ["Master Role", "Derived Role", "Derived Role Description"],
        [
            # Create brand-new CC 3000 derived roles
            ["Z_FI_PERIOD_CONTROL", "Z_FI_PERIOD_CONTROL_3000", "FI GL Period Control - CC 3000"],
            ["Z_MM_PO_PROCESSING", "Z_MM_PO_3000", "MM Purchase Order - Plant 3000"],
            # Existing derived role with blank description (must NOT wipe existing description)
            ["Z_FI_JOURNAL_POST", "Z_FI_JOURNAL_POST_1000", ""],
            # Negative test: missing Master Role
            ["Z_MISSING_MASTER_ROLE", "Z_ORPHAN_DERIVED_3000", "Missing Parent Test"],
            # Negative test: target is an existing Composite Role (must be rejected)
            ["Z_FI_PERIOD_CONTROL", "Z_FI_COMP_CFO_1000", "Composite Collision Test"],
            # Negative test: >30-char derived role name
            ["Z_FI_PERIOD_CONTROL", "Z_DERIVED_ROLE_NAME_OVER_30_CHARS_X", "Oversized Derived Test"],
        ],
    )

    # 3. Org Levels Delta (Z_ROLE_03A_UPDATE_ORG — Append Only vs Two-Way Sync + ALPHA padding + D3)
    _write_csv(
        os.path.join(SCENARIOS_DIR, "Delta_Role_03a_Org_Levels_converted.csv"),
        ["Role", "Org_Level", "value-low", "value-high"],
        [
            # Test Append vs Sync on Z_FI_JOURNAL_POST_1000:
            # - Append Only (rb_app): adds BUKRS 3000 & PRCTR 0030000100 while keeping BUKRS 1000, KOKRS 1000, WERKS 1000
            # - Two-Way Sync (rb_sync): replaces BUKRS with 3000 only; unlisted $KOKRS/$WERKS -> '*' (if p_astnon='X')
            ["Z_FI_JOURNAL_POST_1000", "$BUKRS", "3000", ""],
            ["Z_FI_JOURNAL_POST_1000", "$PRCTR", "30000100", ""],
            # Test new CC 3000 derived role with range + space literal
            ["Z_FI_PERIOD_CONTROL_3000", "$CEERKRS", "1000", ""],
            ["Z_FI_PERIOD_CONTROL_3000", "$KOKRS", "1000", ""],
            ["Z_FI_PERIOD_CONTROL_3000", "$BUKRS", "3000", ""],
            ["Z_FI_PERIOD_CONTROL_3000", "$WERKS", "3000", ""],
            ["Z_FI_PERIOD_CONTROL_3000", "$PRCTR", "30000100", "30009999"],
            ["Z_FI_PERIOD_CONTROL_3000", "$PRCTR", "' '", ""],
            # Test MM Plant 3000 with multiple purchasing groups
            ["Z_MM_PO_3000", "$BUKRS", "3000", ""],
            ["Z_MM_PO_3000", "$WERKS", "3000", ""],
            ["Z_MM_PO_3000", "$EKORG", "3000", ""],
            ["Z_MM_PO_3000", "$EKGRP", "001", ""],
            ["Z_MM_PO_3000", "$EKGRP", "003", ""],
            # Negative test: nonexistent role
            ["Z_NONEXISTENT_ORG_ROLE", "$BUKRS", "1000", ""],
        ],
    )

    # 4. Auth Objects Delta (Z_ROLE_03B_UPDATE_OBJECT — Sync vs Append + ALPHA/NUMC + Org Guard)
    _write_csv(
        os.path.join(SCENARIOS_DIR, "Delta_Role_03b_Auth_Objects_converted.csv"),
        ["Role", "object-field", "value-low", "value-high"],
        [
            # Valid object-field updates with ALPHA padding (KOSTL) and NUMC 8 padding (PS_VERNR)
            ["Z_CO_COST_CENTER_1000", "K_CSKS-KOSTL", "10002000", "10002999"],
            ["Z_MM_INVENTORY_1000", "M_MSEG_LGO-LGORT", "0004", ""],
            ["Z_PS_PROJECT_1000", "C_PROJ_VNR-PS_VERNR", "90", ""],
            ["Z_PS_PROJECT_1000", "C_PRPS_VNR-PS_VERNR", "90", ""],
            # Guard test 1: Org Level field (BUKRS) must be skipped/blocked in 03b (belongs to 03a)
            ["Z_FI_JOURNAL_POST_1000", "F_BKPF_BUK-BUKRS", "9999", ""],
            # Guard test 2: Unassigned object on role (zero foreign object injection)
            ["Z_FI_PERIOD_CONTROL_1000", "M_BEST_WRK-ACTVT", "03", ""],
            # Guard test 3: Nonexistent role
            ["Z_NONEXISTENT_OBJ_ROLE", "K_CSKS-KOSTL", "1000*", ""],
        ],
    )

    # 5. Activity Delta (Z_ROLE_03C_UPDATE_ACTIVITY — Sync vs Append + USORG Block Guard)
    _write_csv(
        os.path.join(SCENARIOS_DIR, "Delta_Role_03c_Activity_converted.csv"),
        ["Role", "Field", "value-low", "value-high"],
        [
            # Restrict display role to read-only (03, F4)
            ["Z_FI_JOURNAL_DISP_1000", "ACTVT", "03", ""],
            ["Z_FI_JOURNAL_DISP_1000", "ACTVT", "F4", ""],
            # Add Change (02) to read-only PS project role (test Append vs Sync)
            ["Z_PS_PROJECT_2000", "PS_ACTVT", "02", ""],
            ["Z_PS_PROJECT_2000", "PS_ACTVT", "03", ""],
            # Guard test: Org Level field (BUKRS) must be blocked by USORG check in 03c
            ["Z_FI_JOURNAL_POST_1000", "BUKRS", "1000", ""],
            # Guard test: Nonexistent role
            ["Z_NONEXISTENT_ACT_ROLE", "ACTVT", "03", ""],
        ],
    )

    # 6. Composite Role Delta (Z_ROLE_04_CREATE_COMPOSITE — Sync vs Append + Nested Comp Guard)
    _write_csv(
        os.path.join(SCENARIOS_DIR, "Delta_Role_04_Composite_converted.csv"),
        ["Composite Role", "Description", "Single Role"],
        [
            # Update existing composite: add Z_FI_ASSET_1000, omit Z_FI_JOURNAL_DISP_1000
            ["Z_FI_COMP_CFO_1000", "Chief Financial Officer - CC 1000", "Z_FI_PERIOD_CONTROL_1000"],
            ["Z_FI_COMP_CFO_1000", "Chief Financial Officer - CC 1000", "Z_FI_JOURNAL_POST_1000"],
            ["Z_FI_COMP_CFO_1000", "Chief Financial Officer - CC 1000", "Z_CO_COST_CENTER_1000"],
            ["Z_FI_COMP_CFO_1000", "Chief Financial Officer - CC 1000", "Z_FI_ASSET_1000"],
            # Guard test 1: Existing composite with blank desc (must NOT wipe description) + missing single role
            ["Z_MM_COMP_PURCHASER_1000", "", "Z_MM_PR_1000"],
            ["Z_MM_COMP_PURCHASER_1000", "", "Z_MM_PO_1000"],
            ["Z_MM_COMP_PURCHASER_1000", "", "Z_MISSING_SINGLE_ROLE_99"],
            # Guard test 2: Nested composite role inside composite role (must report separately as nested composite)
            ["Z_FI_COMP_CONTROLLER_1000", "Financial Controller - CC 1000", "Z_FI_PERIOD_CONTROL_1000"],
            ["Z_FI_COMP_CONTROLLER_1000", "Financial Controller - CC 1000", "Z_FI_COMP_ACCOUNTANT_1000"],
            # Guard test 3: >30-char composite role name
            ["Z_COMPOSITE_ROLE_NAME_EXCEEDS_30_CHR", "Oversized Composite Test", "Z_FI_PERIOD_CONTROL_1000"],
        ],
    )

    # 7. User Creation/Update Delta (Z_USER_01_CREATE — Stale Pwd, Invalid Email, RFC 4180, >12-char)
    _write_csv(
        os.path.join(SCENARIOS_DIR, "Delta_User_01_Create_converted.csv"),
        ["Username", "Full Name", "Email", "Phone No.", "Department", "Function", "Initial Password"],
        [
            # Row 1: Update existing user with explicit password & comma inside quoted Department (RFC 4180)
            ["JOHND", "John Doe", "johnd@example.com", "(84)999999999", "Finance, Tax & Treasury", "VP Finance", "NewPass@2026"],
            # Row 2: Existing user with BLANK password immediately after Row 1 (verifies ZERO password bleed!)
            ["JANES", "Jane Smith", "janes@example.com", "(84)999999999", "Finance & Accounting", "Lead Accountant", ""],
            # Row 3: Existing user with INVALID email while p_sync='X' (must show [WARN] and NOT wipe valid SAP email!)
            ["ALEXJ", "Alex Johnson", "not-a-valid-email", "(1)9999999999", "Controlling", "Senior Controller", ""],
            # Row 4: Brand-new Vietnamese UTF-8 user with auto-generated password
            ["USER_VN04", "Phạm Thị D", "user_vn04@example.com", "(84)999999104", "Kế toán", "Chuyên viên Thuế", ""],
            # Row 5: Negative test — username > 12 chars (must be rejected BEFORE CHAR12 truncation)
            ["OVERSIZED_USER_12345", "Oversized Username", "over@example.com", "(84)999999999", "Testing", "QA", ""],
            # Row 6: Negative test — missing Full Name (mandatory LASTNAME)
            ["NO_NAME_USR", "", "noname@example.com", "", "Testing", "QA", ""],
        ],
    )

    # 8. User Role Assignment Delta (Z_USER_02_ASSIGN_ROLE — Valid Period Preservation, Dedup, Guards)
    _write_csv(
        os.path.join(SCENARIOS_DIR, "Delta_User_02_Assign_converted.csv"),
        ["Username", "Role"],
        [
            # Already assigned in Round 1 -> verifies existing older valid period is preserved (no duplicate rows!)
            ["JOHND", "CR_COMMON"],
            ["JOHND", "Z_FI_COMP_CFO_1000"],
            # Newly added role for existing user (Append adds this without duplicating old roles)
            ["JOHND", "Z_FI_COMP_AUDITOR_RO"],
            # Newly created user from Delta_User_01
            ["USER_VN04", "CR_COMMON"],
            ["USER_VN04", "Z_FI_COMP_ACCOUNTANT_1000"],
            # Negative test 1: Nonexistent SAP user
            ["NO_SUCH_USR", "CR_COMMON"],
            # Negative test 2: Nonexistent SAP role
            ["JANES", "Z_NONEXISTENT_ROLE_99"],
            # Negative test 3: Oversized >12-char username
            ["TOO_LONG_USERNAME_99", "CR_COMMON"],
        ],
    )

    # 9. Step-by-Step Test Scenarios Guide
    guide_path = os.path.join(SCENARIOS_DIR, "README_TEST_SCENARIOS.md")
    guide_content = """# SAP Basis Utilities — Comprehensive End-to-End Test Scenarios

All files in `excel-templates/converted/` (Round 1 — Baseline) and `excel-templates/test-scenarios/` (Round 2 — Delta & Edge Cases) are auto-generated by:

```bash
python scripts/create_templates.py
```

---

## Round 1: Full Multi-Module Baseline Creation (`excel-templates/converted/`)

Run in strict order (first with **Simulation `p_test = 'X'`**, then Live `p_test = ' '`):

| Step | SAP Program | Input CSV (`excel-templates/converted/`) | What It Tests |
| :---: | :--- | :--- | :--- |
| 1 | `Z_ROLE_01_CREATE_MASTER` | `Template_Role_01_Master_converted.csv` | 14 Master Roles across FI, FI-AA, CO, MM, SD, PS + 1 empty-menu role (`Z_FI_GL_REPORTS_EMPTY`) |
| 2 | `Z_ROLE_02_CREATE_DERIVE` | `Template_Role_02_Derived_converted.csv` | 27 Derived Roles across CC/Plant `1000`/`2000`, multi-CC `1000;2000;3000`, Sales Orgs, Purchasing Orgs |
| 3a | `Z_ROLE_03A_UPDATE_ORG` | `Template_Role_03a_Org_Levels_converted.csv` | Mode 1 (`rb_m_csv`) + `rb_sync` + `p_astnon='X'`: `$CEERKRS`, `$KOKRS`, `$BUKRS`, `$WERKS`, `$EKORG`, `$EKGRP`, `$VKORG`, `$VTWEG`, `$SPART`, `$PRCTR` (ranges, `' '`, ALPHA padding) + D3 `'*'` for unlisted Org Levels |
| 3b | `Z_ROLE_03B_UPDATE_OBJECT` | `Template_Role_03b_Auth_Objects_converted.csv` | Non-org fields (`KOSTL`, `LGORT`, `FRGGR`, `FRGCO`, `AUFART`, `ANLKL`, `SEGMENT`, `BUPLA`, `UKM_SGMNT`, `KLVAR`, `PS_VERNR` NUMC 8) |
| 3c | `Z_ROLE_03C_UPDATE_ACTIVITY` | `Template_Role_03c_Activity_converted.csv` | `ACTVT` & `PS_ACTVT` values (`*`, `03, F4`, `01, 02, 03, 77`) |
| 4 | `Z_ROLE_04_CREATE_COMPOSITE` | `Template_Role_04_Composite_converted.csv` | 10 Composite Roles aligned 100% with Step 2 Derived Roles + 1 Empty Composite Role (`Z_COMP_EMPTY_TEST`) |
| 5 | `Z_USER_01_CREATE` | `Template_User_01_Create_converted.csv` + `Template_User_Create_Parameter_converted.csv` | 16 users (EN + Vietnamese UTF-8 names `Nguyễn Văn A`, `Trần Thị B`, `Lê Văn C`, explicit & auto passwords, invalid email `emilyd`, anti-spam note) + all 10 SU01 Parameter slots |
| 6 | `Z_USER_02_ASSIGN_ROLE` | `Template_User_02_Assign_converted.csv` | Mass assignment of Composite + Single Roles (`CR_COMMON` + module roles) |

---

## Round 2: Delta, Sync vs Append & Guard Tests (`excel-templates/test-scenarios/`)

| Step | SAP Program | Input CSV (`excel-templates/test-scenarios/`) | Key Checks & Expected Results |
| :---: | :--- | :--- | :--- |
| 1 | `Z_ROLE_01_CREATE_MASTER` | `Delta_Role_01_Master_converted.csv` | Test `rb_app` (keeps `F-02` + adds `FB65`) vs `rb_sync` (removes `F-02`); warns on `Z_INVALID_TCODE_99`; rejects existing Composite `Z_FI_COMP_CFO_1000` and >30-char role name |
| 2 | `Z_ROLE_02_CREATE_DERIVE` | `Delta_Role_02_Derived_converted.csv` | Creates CC `3000` derived roles; preserves existing description on `Z_FI_JOURNAL_POST_1000`; rejects missing parent, composite collision, and >30-char name |
| 3a-1 | `Z_ROLE_03A_UPDATE_ORG` (`rb_m_csv`) | `Delta_Role_03a_Org_Levels_converted.csv` | **Run with `rb_app` (Append Only)** first: `Z_FI_JOURNAL_POST_1000` keeps `1000` AND adds `3000` + `0030000100`; then simulate with `rb_sync` (Two-Way Sync): unlisted `$KOKRS`/`$WERKS` default to `'*'` (`p_astnon='X'`); errors on `Z_NONEXISTENT_ORG_ROLE` |
| 3a-2 | `Z_ROLE_03A_UPDATE_ORG` (`rb_m_fix`) | `s_role = Z_FI_*` (or CSV) | **Merged Repair `$VARBL` Mode**: Scans `AGR_1251`/`AGR_1250`, heals broken `$VARBL` bindings and parent Master Roles (`p_parhea='X'`), preserves existing valid `AGR_1252` values |
| 3b | `Z_ROLE_03B_UPDATE_OBJECT` | `Delta_Role_03b_Auth_Objects_converted.csv` | Updates `KOSTL`, `LGORT`, `PS_VERNR` (`90` -> `00000090`); skips/blocks `F_BKPF_BUK-BUKRS` (Org Level); skips unassigned object `M_BEST_WRK` |
| 3c | `Z_ROLE_03C_UPDATE_ACTIVITY` | `Delta_Role_03c_Activity_converted.csv` | Updates `ACTVT` & `PS_ACTVT` in Append vs Sync; blocks `BUKRS` (USORG guard) |
| 4 | `Z_ROLE_04_CREATE_COMPOSITE` | `Delta_Role_04_Composite_converted.csv` | Tests Sync vs Append on `Z_FI_COMP_CFO_1000`; preserves blank desc on `Z_MM_COMP_PURCHASER_1000`; reports missing single role vs nested composite (`Z_FI_COMP_ACCOUNTANT_1000`) separately; blocks >30-char name |
| 5 | `Z_USER_01_CREATE` | `Delta_User_01_Create_converted.csv` | Run with `p_upd='X'`, `p_sync='X'`, `p_pwd='X'`: verifies RFC 4180 quoted comma `"Finance, Tax & Treasury"`, **zero password bleed** from `JOHND` to `JANES`, **`[WARN]` without wiping `ALEXJ` email**, creates UTF-8 `USER_VN04`, rejects >12-char `OVERSIZED_USER_12345` & blank name `NO_NAME_USR` |
| 6 | `Z_USER_02_ASSIGN_ROLE` | `Delta_User_02_Assign_converted.csv` | Run with `p_append='X'` & `p_dedup='X'`: preserves older valid periods on `JOHND` (zero duplicates!), adds `Z_FI_COMP_AUDITOR_RO`, assigns roles to `USER_VN04`, rejects `NO_SUCH_USR`, `Z_NONEXISTENT_ROLE_99`, and >12-char `TOO_LONG_USERNAME_99` |
"""
    with open(guide_path, 'w', encoding='utf-8') as f:
        f.write(guide_content.strip() + "\n")
    print(f"[OK] Generated test scenarios guide: {guide_path}")


# --- CLI Entrypoint ---
if __name__ == "__main__":
    print("\n--- Generating Comprehensive SAP Role & User Templates + Test Scenarios ---")
    create_consolidated_role_template()
    create_consolidated_user_template()
    create_delta_test_scenarios()
    print("\n[OK] All templates, converted CSVs, and Round-2 test scenarios generated successfully.")
