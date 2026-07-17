from pathlib import Path
from xml.sax.saxutils import escape

from bs4 import BeautifulSoup, NavigableString, Tag
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, Frame, Image, KeepTogether, PageBreak, PageTemplate,
    Paragraph, Spacer, Table, TableStyle,
)

ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "docs/GUIA_COMPLETA_ARKGO.html"
PDF = ROOT / "docs/GUIA_COMPLETA_ARKGO.pdf"
FONT_DIR = Path("/usr/share/fonts/TTF")
pdfmetrics.registerFont(TTFont("DejaVu", FONT_DIR / "Lato-Regular.ttf"))
pdfmetrics.registerFont(TTFont("DejaVu-Bold", FONT_DIR / "Lato-Bold.ttf"))
pdfmetrics.registerFont(TTFont("DejaVu-Oblique", FONT_DIR / "Lato-Italic.ttf"))

NAVY = colors.HexColor("#112B46")
TEAL = colors.HexColor("#1B5E72")
GOLD = colors.HexColor("#E7A928")
MUTED = colors.HexColor("#667085")

styles = getSampleStyleSheet()
styles.add(ParagraphStyle("BodyArk", parent=styles["BodyText"], fontName="DejaVu", fontSize=9.1, leading=13, textColor=colors.HexColor("#182230"), spaceAfter=5))
styles.add(ParagraphStyle("H1Ark", parent=styles["Heading1"], fontName="DejaVu-Bold", fontSize=19, leading=23, textColor=NAVY, spaceBefore=12, spaceAfter=7, keepWithNext=True))
styles.add(ParagraphStyle("H2Ark", parent=styles["Heading2"], fontName="DejaVu-Bold", fontSize=12.2, leading=15, textColor=TEAL, spaceBefore=9, spaceAfter=4, keepWithNext=True))
styles.add(ParagraphStyle("H3Ark", parent=styles["Heading3"], fontName="DejaVu-Bold", fontSize=10, leading=13, textColor=TEAL, spaceBefore=6, spaceAfter=3, keepWithNext=True))
styles.add(ParagraphStyle("SmallArk", parent=styles["BodyText"], fontName="DejaVu", fontSize=7.7, leading=10, textColor=MUTED, spaceAfter=4))
styles.add(ParagraphStyle("TableArk", parent=styles["BodyText"], fontName="DejaVu", fontSize=7.1, leading=9, textColor=colors.HexColor("#182230")))
styles.add(ParagraphStyle("TableHeadArk", parent=styles["TableArk"], fontName="DejaVu-Bold", textColor=colors.white))
styles.add(ParagraphStyle("CodeArk", parent=styles["Code"], fontName="DejaVu", fontSize=7.3, leading=10, backColor=colors.HexColor("#F1F3F5"), borderPadding=3))
styles.add(ParagraphStyle("PreArk", parent=styles["Code"], fontName="DejaVu", fontSize=7.1, leading=9, textColor=colors.HexColor("#EFF5F8"), backColor=colors.HexColor("#142333"), borderPadding=7))
styles.add(ParagraphStyle("CoverTitle", parent=styles["Title"], fontName="DejaVu-Bold", fontSize=29, leading=34, textColor=NAVY, alignment=TA_LEFT, spaceAfter=10))
styles.add(ParagraphStyle("CoverSub", parent=styles["BodyText"], fontName="DejaVu", fontSize=14, leading=18, textColor=colors.HexColor("#526273"), spaceAfter=12))

def inline(node):
    if isinstance(node, NavigableString):
        return escape(str(node)).replace("\n", " ")
    if not isinstance(node, Tag):
        return ""
    content = "".join(inline(c) for c in node.children)
    if node.name in ("strong", "b"):
        return f"<b>{content}</b>"
    if node.name in ("em", "i"):
        return f"<i>{content}</i>"
    if node.name == "code":
        return f"<font name='DejaVu' backColor='#F1F3F5'>{content}</font>"
    return content

def para(text, style="BodyArk"):
    return Paragraph(text.strip(), styles[style])

def cell_content(cell, head=False):
    return para(inline(cell), "TableHeadArk" if head else "TableArk")

def footer(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(colors.HexColor("#D9E0E7"))
    canvas.line(16 * mm, 13 * mm, A4[0] - 16 * mm, 13 * mm)
    canvas.setFont("DejaVu", 7)
    canvas.setFillColor(MUTED)
    canvas.drawRightString(A4[0] - 16 * mm, 8 * mm, f"ArkGO • Guia completo • {doc.page}")
    canvas.restoreState()

def build():
    soup = BeautifulSoup(HTML.read_text(encoding="utf-8"), "html.parser")
    story = []
    cover = soup.select_one("section.cover")
    if cover:
        logo = ROOT / "assets/arkgo-logo.png"
        if logo.exists():
            story.append(Image(str(logo), width=25 * mm, height=25 * mm))
            story.append(Spacer(1, 8 * mm))
        story += [para("DOCUMENTAÇÃO OFICIAL DO PROJETO", "H3Ark"), para("ArkGO", "CoverTitle"), para("Guia completo do produto, operação, arquitetura e próximos passos", "CoverSub"), para("Aplicativo de intermediação logística urbana para conectar clientes a motoboys e outros veículos de entrega.", "BodyArk"), Spacer(1, 35 * mm)]
        story.append(para("<b>Versão do documento:</b> 1.0<br/><b>Data de referência:</b> 17 de julho de 2026<br/><b>Local do projeto:</b> <font name='DejaVu'>UrbGO/urbgo</font><br/><b>Nome técnico do pacote:</b> arkgo", "SmallArk"))
        story.append(PageBreak())
    body = soup.body
    for node in body.children:
        if not isinstance(node, Tag) or node.name == "section":
            continue
        if node.name in ("h2", "h3", "h4"):
            style = "H1Ark" if node.name == "h2" else ("H2Ark" if node.name == "h3" else "H3Ark")
            story.append(para(inline(node), style))
        elif node.name == "p":
            cls = node.get("class", [])
            story.append(para(inline(node), "SmallArk" if "small" in cls else "BodyArk"))
        elif node.name in ("ul", "ol"):
            for i, li in enumerate(node.find_all("li", recursive=False), 1):
                mark = f"{i}." if node.name == "ol" else "•"
                story.append(para(f"{mark} {inline(li)}", "BodyArk"))
        elif node.name == "table":
            rows = []
            for tr in node.find_all("tr", recursive=False):
                cells = tr.find_all(["th", "td"], recursive=False)
                rows.append([cell_content(c, c.name == "th") for c in cells])
            if rows:
                n = len(rows[0])
                widths = [((A4[0] - 32 * mm) / n)] * n
                table = Table(rows, colWidths=widths, repeatRows=1)
                commands = [("GRID", (0, 0), (-1, -1), .35, colors.HexColor("#D9E0E7")), ("VALIGN", (0, 0), (-1, -1), "TOP"), ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4), ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4)]
                if node.find("th"):
                    commands += [("BACKGROUND", (0, 0), (-1, 0), NAVY), ("TEXTCOLOR", (0, 0), (-1, 0), colors.white)]
                for r in range(1, len(rows)):
                    if r % 2 == 0:
                        commands.append(("BACKGROUND", (0, r), (-1, r), colors.HexColor("#F7F9FB")))
                table.setStyle(TableStyle(commands))
                story.append(table)
                story.append(Spacer(1, 4))
        elif node.name == "div":
            cls = node.get("class", [])
            if "diagram" in cls:
                story.append(para(escape(node.get_text("\n", strip=False)), "PreArk"))
            elif "box" in cls:
                bg = "#EAF7F8" if "info" in cls else ("#EDF8F1" if "ok" in cls else ("#FFF0EE" if "warn" in cls else "#FFF8E8"))
                box = Table([[para(inline(node), "BodyArk")]], colWidths=[A4[0] - 32 * mm])
                box.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), colors.HexColor(bg)), ("BOX", (0, 0), (-1, -1), .4, GOLD), ("LEFTPADDING", (0, 0), (-1, -1), 8), ("RIGHTPADDING", (0, 0), (-1, -1), 8), ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]))
                story.append(box)
        elif node.name == "pre":
            story.append(para(escape(node.get_text()), "PreArk"))
    doc = BaseDocTemplate(str(PDF), pagesize=A4, leftMargin=16 * mm, rightMargin=16 * mm, topMargin=15 * mm, bottomMargin=18 * mm, title="ArkGO — Guia completo do produto e projeto", author="ArkGO")
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="normal")
    doc.addPageTemplates([PageTemplate(id="arkgo", frames=frame, onPage=footer)])
    doc.build(story)

if __name__ == "__main__":
    build()
