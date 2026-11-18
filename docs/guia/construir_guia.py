# -*- coding: utf-8 -*-
"""Genera la guía de configuración de routers para la sustentación en .docx.

Uso:
    python docs/guia/construir_guia.py

Requiere python-docx. Las figuras se exportan aparte desde los .drawio con
draw.io de escritorio y se guardan en docs/guia/figuras/.
"""

from pathlib import Path
import re
import tempfile

from PIL import Image
from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_ALIGN_VERTICAL, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_TAB_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

RAIZ = Path(__file__).resolve().parents[2]
FIGURAS = RAIZ / "docs" / "guia" / "figuras"
SALIDA = RAIZ / "docs" / "guia-routers-sustentacion.docx"
CACHE_FIGURAS = Path(tempfile.gettempdir()) / "guia-figuras"
ANCHO_MAX_FIGURA = 1400

AZUL = RGBColor(0x1B, 0x1F, 0x24)
AZUL_MEDIO = RGBColor(0x2F, 0x4A, 0x6B)
GRIS = RGBColor(0x5B, 0x64, 0x74)
GRIS_CLARO = RGBColor(0x6B, 0x72, 0x80)
VERDE = RGBColor(0x2F, 0x6B, 0x45)
AMBAR = RGBColor(0x8A, 0x53, 0x09)
ROJO = RGBColor(0x9B, 0x2C, 0x2C)

FUENTE_CUERPO = "Calibri"
FUENTE_TITULO = "Calibri"
FUENTE_CODIGO = "Consolas"

ANCHO_UTIL = Cm(17.0)

# Orden de los hijos según el esquema de Word. Insertar fuera de orden hace que
# Word tolerere el archivo al leerlo pero se cuelgue al guardar o exportar.
ORDEN_TCPR = [
    "w:cnfStyle", "w:tcW", "w:gridSpan", "w:hMerge", "w:vMerge", "w:tcBorders",
    "w:shd", "w:noWrap", "w:tcMar", "w:textDirection", "w:tcFitText", "w:vAlign",
    "w:hideMark",
]
ORDEN_TBLPR = [
    "w:tblStyle", "w:tblpPr", "w:tblOverlap", "w:bidiVisual",
    "w:tblStyleRowBandSize", "w:tblStyleColBandSize", "w:tblW", "w:jc",
    "w:tblCellSpacing", "w:tblInd", "w:tblBorders", "w:shd", "w:tblLayout",
    "w:tblCellMar", "w:tblLook", "w:tblCaption", "w:tblDescription",
]
ORDEN_PPR = [
    "w:pStyle", "w:keepNext", "w:keepLines", "w:pageBreakBefore", "w:framePr",
    "w:widowControl", "w:numPr", "w:suppressLineNumbers", "w:pBdr", "w:shd",
    "w:tabs", "w:suppressAutoHyphens", "w:kinsoku", "w:wordWrap",
    "w:overflowPunct", "w:topLinePunct", "w:autoSpaceDE", "w:autoSpaceDN",
    "w:bidi", "w:adjustRightInd", "w:snapToGrid", "w:spacing", "w:ind",
    "w:contextualSpacing", "w:mirrorIndents", "w:suppressOverlap", "w:jc",
    "w:textDirection", "w:textAlignment", "w:textboxTightWrap", "w:outlineLvl",
    "w:divId", "w:cnfStyle", "w:rPr", "w:sectPr", "w:pPrChange",
]
ORDEN_RPR = [
    "w:rStyle", "w:rFonts", "w:b", "w:bCs", "w:i", "w:iCs", "w:caps",
    "w:smallCaps", "w:strike", "w:dstrike", "w:outline", "w:shadow",
    "w:emboss", "w:imprint", "w:noProof", "w:snapToGrid", "w:vanish",
    "w:webHidden", "w:color", "w:spacing", "w:w", "w:kern", "w:position",
    "w:sz", "w:szCs", "w:highlight", "w:u", "w:effect", "w:bdr", "w:shd",
    "w:fitText", "w:vertAlign", "w:rtl", "w:cs", "w:em", "w:lang",
    "w:eastAsianLayout", "w:specVanish", "w:oMath",
]
ORDEN_TRPR = [
    "w:cnfStyle", "w:divId", "w:gridBefore", "w:gridAfter", "w:wBefore",
    "w:wAfter", "w:cantSplit", "w:trHeight", "w:tblHeader", "w:tblCellSpacing",
    "w:jc", "w:hidden",
]


def _insertar_ordenado(padre, hijo, orden):
    """Inserta (o reemplaza) un hijo respetando el orden del esquema OOXML."""
    etiqueta = hijo.tag
    for previo in padre.findall(etiqueta):
        padre.remove(previo)
    nombre = None
    for candidato in orden:
        if qn(candidato) == etiqueta:
            nombre = candidato
            break
    if nombre is None:
        padre.append(hijo)
        return
    sucesores = orden[orden.index(nombre) + 1:]
    for siguiente in sucesores:
        existente = padre.find(qn(siguiente))
        if existente is not None:
            existente.addprevious(hijo)
            return
    padre.append(hijo)


# ---------------------------------------------------------------------------
# Utilidades de bajo nivel (XML de Word)
# ---------------------------------------------------------------------------


def _shade(elemento, relleno, orden):
    """Aplica sombreado a una celda o a una run respetando el orden del esquema."""
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), relleno)
    _insertar_ordenado(elemento, shd, orden)


def sombrear_celda(celda, relleno):
    _shade(celda._tc.get_or_add_tcPr(), relleno, ORDEN_TCPR)


def sombrear_run(run, relleno):
    _shade(run._r.get_or_add_rPr(), relleno, ORDEN_RPR)


def bordes_celda(celda, color="C6CDDA", tamano=6, lados=("top", "left", "bottom", "right"),
                 color_izquierda=None, tamano_izquierda=None):
    tcPr = celda._tc.get_or_add_tcPr()
    bordes = OxmlElement("w:tcBorders")
    for lado in ("top", "left", "bottom", "right"):
        b = OxmlElement(f"w:{lado}")
        b.set(qn("w:val"), "single")
        if lado == "left" and color_izquierda:
            b.set(qn("w:sz"), str(tamano_izquierda or tamano))
            b.set(qn("w:color"), color_izquierda)
        else:
            b.set(qn("w:sz"), str(tamano))
            b.set(qn("w:color"), color)
        b.set(qn("w:space"), "0")
        bordes.append(b)
    _insertar_ordenado(tcPr, bordes, ORDEN_TCPR)


def bordes_tabla(tabla, color="C6CDDA", tamano=6):
    tblPr = tabla._tbl.tblPr
    bordes = OxmlElement("w:tblBorders")
    for lado in ("top", "left", "bottom", "right", "insideH", "insideV"):
        b = OxmlElement(f"w:{lado}")
        b.set(qn("w:val"), "single")
        b.set(qn("w:sz"), str(tamano))
        b.set(qn("w:space"), "0")
        b.set(qn("w:color"), color)
        bordes.append(b)
    _insertar_ordenado(tblPr, bordes, ORDEN_TBLPR)


def margenes_celda(celda, arriba=70, abajo=70, izquierda=110, derecha=110):
    tcPr = celda._tc.get_or_add_tcPr()
    mar = OxmlElement("w:tcMar")
    for lado, valor in (("top", arriba), ("left", izquierda), ("bottom", abajo), ("right", derecha)):
        el = OxmlElement(f"w:{lado}")
        el.set(qn("w:w"), str(valor))
        el.set(qn("w:type"), "dxa")
        mar.append(el)
    _insertar_ordenado(tcPr, mar, ORDEN_TCPR)


def no_partir_fila(fila):
    trPr = fila._tr.get_or_add_trPr()
    cant = OxmlElement("w:cantSplit")
    _insertar_ordenado(trPr, cant, ORDEN_TRPR)


def repetir_encabezado(fila):
    trPr = fila._tr.get_or_add_trPr()
    cab = OxmlElement("w:tblHeader")
    _insertar_ordenado(trPr, cab, ORDEN_TRPR)


def ancho_columnas(tabla, anchos_cm):
    tabla.autofit = False
    tblPr = tabla._tbl.tblPr
    layout = OxmlElement("w:tblLayout")
    layout.set(qn("w:type"), "fixed")
    _insertar_ordenado(tblPr, layout, ORDEN_TBLPR)
    for indice, ancho in enumerate(anchos_cm):
        tabla.columns[indice].width = Cm(ancho)
        for celda in tabla.columns[indice].cells:
            celda.width = Cm(ancho)


def campo(parrafo, instruccion, texto_inicial=""):
    """Inserta un campo de Word (PAGE, NUMPAGES, TOC)."""
    run = parrafo.add_run()
    inicio = OxmlElement("w:fldChar")
    inicio.set(qn("w:fldCharType"), "begin")
    texto = OxmlElement("w:instrText")
    texto.set(qn("xml:space"), "preserve")
    texto.text = f" {instruccion} "
    separador = OxmlElement("w:fldChar")
    separador.set(qn("w:fldCharType"), "separate")
    valor = OxmlElement("w:t")
    valor.text = texto_inicial
    fin = OxmlElement("w:fldChar")
    fin.set(qn("w:fldCharType"), "end")
    for el in (inicio, texto, separador, valor, fin):
        run._r.append(el)
    return run


def borde_parrafo(parrafo, color="5B6B8C", tamano=8, lado="bottom"):
    pPr = parrafo._p.get_or_add_pPr()
    pBdr = OxmlElement("w:pBdr")
    b = OxmlElement(f"w:{lado}")
    b.set(qn("w:val"), "single")
    b.set(qn("w:sz"), str(tamano))
    b.set(qn("w:space"), "4")
    b.set(qn("w:color"), color)
    pBdr.append(b)
    _insertar_ordenado(pPr, pBdr, ORDEN_PPR)


def actualizar_campos(doc):
    settings = doc.settings.element
    actualizar = OxmlElement("w:updateFields")
    actualizar.set(qn("w:val"), "true")
    settings.append(actualizar)


def idioma_es(doc):
    rPr = doc.styles["Normal"].element.get_or_add_rPr()
    lang = OxmlElement("w:lang")
    lang.set(qn("w:val"), "es-CO")
    lang.set(qn("w:eastAsia"), "es-CO")
    lang.set(qn("w:bidi"), "ar-SA")
    rPr.append(lang)


def preparar_figura(ruta):
    """Copia la figura a un tamaño manejable para Word (máximo 1800 px de ancho).

    Word se toma varios minutos para exportar el documento cuando incrusta los
    PNG de 2x del export de draw.io; con este tamaño el resultado se ve igual y
    la exportación es inmediata.
    """
    CACHE_FIGURAS.mkdir(parents=True, exist_ok=True)
    destino = CACHE_FIGURAS / f"{ruta.stem}-{ANCHO_MAX_FIGURA}{ruta.suffix}"
    if destino.exists() and destino.stat().st_mtime >= ruta.stat().st_mtime:
        return destino
    imagen = Image.open(ruta).convert("RGB")
    if imagen.width > ANCHO_MAX_FIGURA:
        alto = round(imagen.height * ANCHO_MAX_FIGURA / imagen.width)
        imagen = imagen.resize((ANCHO_MAX_FIGURA, alto), Image.LANCZOS)
    imagen.save(destino, optimize=True)
    return destino


# ---------------------------------------------------------------------------
# Estilos
# ---------------------------------------------------------------------------


def preparar_estilos(doc):
    normal = doc.styles["Normal"]
    normal.font.name = FUENTE_CUERPO
    normal.font.size = Pt(10.5)
    normal.font.color.rgb = RGBColor(0x1F, 0x24, 0x30)
    pf = normal.paragraph_format
    pf.space_after = Pt(5)
    pf.line_spacing = 1.12
    pf.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY

    for nivel, tamano, color, antes, despues in (
        (1, 18, AZUL, 6, 8),
        (2, 13, AZUL_MEDIO, 12, 4),
        (3, 11.5, RGBColor(0x3A, 0x43, 0x54), 8, 3),
    ):
        estilo = doc.styles[f"Heading {nivel}"]
        estilo.font.name = FUENTE_TITULO
        estilo.font.size = Pt(tamano)
        estilo.font.bold = True
        estilo.font.color.rgb = color
        estilo.paragraph_format.space_before = Pt(antes)
        estilo.paragraph_format.space_after = Pt(despues)
        estilo.paragraph_format.keep_with_next = True
        estilo.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
        rPr = estilo.element.get_or_add_rPr()
        rFonts = rPr.find(qn("w:rFonts"))
        if rFonts is None:
            rFonts = OxmlElement("w:rFonts")
            rPr.append(rFonts)
        rFonts.set(qn("w:ascii"), FUENTE_TITULO)
        rFonts.set(qn("w:hAnsi"), FUENTE_TITULO)

    idioma_es(doc)


def configurar_pagina(doc):
    seccion = doc.sections[0]
    seccion.page_width = Cm(21.59)
    seccion.page_height = Cm(27.94)
    seccion.left_margin = Cm(2.2)
    seccion.right_margin = Cm(2.2)
    seccion.top_margin = Cm(2.1)
    seccion.bottom_margin = Cm(2.0)
    seccion.header_distance = Cm(1.0)
    seccion.footer_distance = Cm(0.9)
    seccion.different_first_page_header_footer = True

    encabezado = seccion.header.paragraphs[0]
    encabezado.paragraph_format.tab_stops.add_tab_stop(Cm(17.0), WD_TAB_ALIGNMENT.RIGHT)
    izq = encabezado.add_run("LAN Shooter · Guía de configuración para la sustentación")
    izq.font.size = Pt(8)
    izq.font.color.rgb = GRIS_CLARO
    der = encabezado.add_run("\tRedes de Computadores")
    der.font.size = Pt(8)
    der.font.color.rgb = GRIS_CLARO
    borde_parrafo(encabezado, color="C6CDDA", tamano=6)

    pie = seccion.footer.paragraphs[0]
    pie.alignment = WD_ALIGN_PARAGRAPH.CENTER
    pie.paragraph_format.space_before = Pt(2)
    r = pie.add_run("Página ")
    r.font.size = Pt(8)
    r.font.color.rgb = GRIS_CLARO
    campo(pie, "PAGE", "1")
    r = pie.add_run(" de ")
    r.font.size = Pt(8)
    r.font.color.rgb = GRIS_CLARO
    campo(pie, "NUMPAGES", "1")
    for run in pie.runs:
        run.font.size = Pt(8)
        run.font.color.rgb = GRIS_CLARO


# ---------------------------------------------------------------------------
# Bloques de contenido
# ---------------------------------------------------------------------------


def rich(parrafo, texto, tamano=None, color=None, negrita=False, cursiva=False):
    """Escribe texto con **negrita** y `código` en línea."""
    partes = re.split(r"(\*\*[^*]+\*\*|`[^`]+`)", texto)
    for parte in partes:
        if not parte:
            continue
        if parte.startswith("**") and parte.endswith("**"):
            run = parrafo.add_run(parte[2:-2])
            run.bold = True
        elif parte.startswith("`") and parte.endswith("`"):
            run = parrafo.add_run(parte[1:-1])
            run.font.name = FUENTE_CODIGO
            run.font.size = Pt((tamano or 10.5) - 1)
            run.font.color.rgb = RGBColor(0x8A, 0x3B, 0x12)
            sombrear_run(run, "F1F2F4")
        else:
            run = parrafo.add_run(parte)
            if negrita:
                run.bold = True
            if cursiva:
                run.italic = True
        if tamano:
            if not (parte.startswith("`") and parte.endswith("`")):
                run.font.size = Pt(tamano)
        if color:
            run.font.color.rgb = color
    return parrafo


def parrafo(doc, texto, tamano=None, color=None, cursiva=False, alineacion=None, espacio_antes=None,
            espacio_despues=None, sangria=None):
    p = doc.add_paragraph()
    rich(p, texto, tamano=tamano, color=color, cursiva=cursiva)
    if alineacion is not None:
        p.alignment = alineacion
    if espacio_antes is not None:
        p.paragraph_format.space_before = Pt(espacio_antes)
    if espacio_despues is not None:
        p.paragraph_format.space_after = Pt(espacio_despues)
    if sangria is not None:
        p.paragraph_format.left_indent = Cm(sangria)
    return p


def vinetas(doc, elementos, tamano=10.5):
    for elemento in elementos:
        p = doc.add_paragraph(style="List Bullet")
        p.paragraph_format.space_after = Pt(2)
        p.paragraph_format.left_indent = Cm(0.75)
        p.paragraph_format.first_line_indent = Cm(-0.35)
        # Fija la tabulación de la viñeta para que la sangría no dependa del estilo.
        p.paragraph_format.tab_stops.add_tab_stop(Cm(0.75))
        rich(p, elemento, tamano=tamano)


def pasos(doc, elementos):
    for indice, elemento in enumerate(elementos, start=1):
        p = doc.add_paragraph()
        p.paragraph_format.left_indent = Cm(0.8)
        p.paragraph_format.first_line_indent = Cm(-0.8)
        p.paragraph_format.space_after = Pt(4)
        num = p.add_run(f"{indice}.\t")
        num.bold = True
        num.font.color.rgb = AZUL_MEDIO
        p.paragraph_format.tab_stops.add_tab_stop(Cm(0.8))
        rich(p, elemento)


def subtitulo(doc, texto):
    h = doc.add_heading(texto, level=2)
    return h


def titulo(doc, texto, salto=False):
    h = doc.add_heading(texto, level=1)
    if salto:
        # page_break_before evita la página en blanco que deja un salto manual
        # cuando el capítulo anterior termina justo al pie de página.
        h.paragraph_format.page_break_before = True
    return h


def spacer(doc, puntos=4):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.line_spacing = 1
    run = p.add_run("")
    run.font.size = Pt(puntos)


def bloque_codigo(doc, lineas, ancho=17.0):
    tabla = doc.add_table(rows=1, cols=1)
    tabla.alignment = WD_TABLE_ALIGNMENT.CENTER
    celda = tabla.cell(0, 0)
    celda.width = Cm(ancho)
    sombrear_celda(celda, "F4F5F7")
    bordes_celda(celda, color="DDE1E8", tamano=6)
    margenes_celda(celda, arriba=90, abajo=90, izquierda=160, derecha=120)
    p = celda.paragraphs[0]
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.line_spacing = 1.0
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    primera = True
    for linea in lineas.split("\n"):
        if not primera:
            p = celda.add_paragraph()
            p.paragraph_format.space_after = Pt(0)
            p.paragraph_format.space_before = Pt(0)
            p.paragraph_format.line_spacing = 1.0
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        run = p.add_run(linea if linea else " ")
        run.font.name = FUENTE_CODIGO
        run.font.size = Pt(8.5)
        run.font.color.rgb = RGBColor(0x1F, 0x24, 0x30)
        primera = False
    no_partir_fila(tabla.rows[0])
    spacer(doc, 2)


def aviso(doc, titulo_aviso, texto, tipo="ojo"):
    colores = {
        "ojo": ("FFF8E1", "B45309", AMBAR),
        "bien": ("EAF6EE", "3F8F5C", VERDE),
        "mal": ("FBEDED", "9B2C2C", ROJO),
        "info": ("EEF3FA", "5B6B8C", AZUL_MEDIO),
    }
    relleno, borde, color_titulo = colores[tipo]
    tabla = doc.add_table(rows=1, cols=1)
    tabla.alignment = WD_TABLE_ALIGNMENT.CENTER
    celda = tabla.cell(0, 0)
    celda.width = Cm(17.0)
    sombrear_celda(celda, relleno)
    bordes_celda(celda, color=relleno, tamano=4, color_izquierda=borde, tamano_izquierda=24)
    margenes_celda(celda, arriba=90, abajo=90, izquierda=170, derecha=150)

    p = celda.paragraphs[0]
    p.paragraph_format.space_after = Pt(2)
    r = p.add_run(titulo_aviso)
    r.bold = True
    r.font.size = Pt(9.5)
    r.font.color.rgb = color_titulo
    p2 = celda.add_paragraph()
    p2.paragraph_format.space_after = Pt(0)
    rich(p2, texto, tamano=9.5)
    no_partir_fila(tabla.rows[0])
    spacer(doc, 2)


def figura(doc, archivo, numero, leyenda, ancho_cm=16.2, fuente=None):
    ruta = FIGURAS / archivo
    if not ruta.exists():
        ruta = RAIZ / "docs" / archivo
    ruta = preparar_figura(ruta)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(6)
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.keep_with_next = True
    p.add_run().add_picture(str(ruta), width=Cm(ancho_cm))
    cap = doc.add_paragraph()
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cap.paragraph_format.space_after = Pt(8)
    r = cap.add_run(f"Figura {numero}. ")
    r.bold = True
    r.font.size = Pt(8.5)
    r.font.color.rgb = GRIS
    r2 = cap.add_run(leyenda)
    r2.font.size = Pt(8.5)
    r2.font.color.rgb = GRIS
    if fuente:
        r3 = cap.add_run(f" {fuente}")
        r3.font.size = Pt(8)
        r3.font.color.rgb = GRIS_CLARO
        r3.italic = True


def rich_cabecera(parrafo, texto, tamano):
    """Escribe una celda de encabezado admitiendo `código` en línea."""
    for parte in re.split(r"(`[^`]+`)", texto):
        if not parte:
            continue
        if parte.startswith("`") and parte.endswith("`"):
            run = parrafo.add_run(parte[1:-1])
            run.font.name = FUENTE_CODIGO
            run.font.size = Pt(tamano - 0.5)
            run.bold = True
            run.font.color.rgb = RGBColor(0x8A, 0x3B, 0x12)
        else:
            run = parrafo.add_run(parte)
            run.bold = True
            run.font.size = Pt(tamano)
            run.font.color.rgb = AZUL


def tabla(doc, encabezados, filas, anchos=None, tamano=9.5, primera_columna_bold=False,
          mantener_junto=True):
    # Si la tabla va a quedarse entera, el párrafo que la introduce la acompaña:
    # así no queda un título al pie de una página y la tabla en la siguiente.
    anterior = doc.paragraphs[-1] if doc.paragraphs else None
    t = doc.add_table(rows=1, cols=len(encabezados))
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    bordes_tabla(t)
    cab = t.rows[0]
    repetir_encabezado(cab)
    for indice, texto in enumerate(encabezados):
        celda = cab.cells[indice]
        sombrear_celda(celda, "E8ECF3")
        margenes_celda(celda)
        celda.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        p = celda.paragraphs[0]
        p.paragraph_format.space_after = Pt(0)
        p.paragraph_format.space_before = Pt(0)
        rich_cabecera(p, texto, tamano)
    for fila in filas:
        celdas = t.add_row().cells
        for indice, valor in enumerate(fila):
            celda = celdas[indice]
            margenes_celda(celda)
            celda.vertical_alignment = WD_ALIGN_VERTICAL.TOP
            p = celda.paragraphs[0]
            p.paragraph_format.space_after = Pt(0)
            p.paragraph_format.space_before = Pt(0)
            p.paragraph_format.line_spacing = 1.05
            rich(p, str(valor), tamano=tamano, negrita=(primera_columna_bold and indice == 0))
    if anchos:
        ancho_columnas(t, anchos)
    # Las tablas cortas se mantienen enteras: partir una fila sola al pie de la
    # página deja una página casi vacía y se lee mal.
    if mantener_junto and len(t.rows) <= 10:
        for fila in t.rows[:-1]:
            for celda in fila.cells:
                for p in celda.paragraphs:
                    p.paragraph_format.keep_with_next = True
        if anterior is not None:
            anterior.paragraph_format.keep_with_next = True
    spacer(doc, 3)
    return t


def campo_toc(doc):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(6)
    campo(p, 'TOC \\o "1-1" \\h \\z \\u', "Tabla de contenido")


def encabezado_seccion(doc, texto):
    h = doc.add_heading(texto, level=2)
    return h


# ---------------------------------------------------------------------------
# Documento
# ---------------------------------------------------------------------------


def portada(doc):
    spacer(doc, 30)
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(0)
    r = p.add_run("GUÍA DE CONFIGURACIÓN")
    r.font.size = Pt(10)
    r.font.bold = True
    r.font.color.rgb = AMBAR
    r.font.name = FUENTE_TITULO

    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after = Pt(4)
    r = p.add_run("Cómo montar la red del juego\nen la sustentación")
    r.font.size = Pt(30)
    r.font.bold = True
    r.font.color.rgb = AZUL
    r.font.name = FUENTE_TITULO
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT

    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(10)
    r = p.add_run("Dos routers, dos PC y un cable de consola")
    r.font.size = Pt(15)
    r.font.color.rgb = GRIS

    linea = doc.add_paragraph()
    linea.paragraph_format.space_after = Pt(12)
    borde_parrafo(linea, color="B45309", tamano=12)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(8)
    p.paragraph_format.space_after = Pt(14)
    p.add_run().add_picture(str(preparar_figura(FIGURAS / "03-montaje.png")), width=Cm(16.4))

    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(2)
    r = p.add_run("LAN Shooter")
    r.bold = True
    r.font.size = Pt(12)
    r.font.color.rgb = AZUL

    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(2)
    rich(p, "Juego multijugador cliente-servidor sobre una red LAN–WAN–LAN, con UDP en el puerto 9999.",
         tamano=10.5, color=GRIS)

    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(18)
    p.paragraph_format.space_after = Pt(2)
    r = p.add_run("Redes de Computadores · Sustentación")
    r.bold = True
    r.font.size = Pt(11)
    r.font.color.rgb = AZUL

    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(2)
    r = p.add_run("Martin Pineda Jaramillo · David Felipe Beltran Tabares · Juan David Navarro Bermudez")
    r.font.size = Pt(9.5)
    r.font.color.rgb = GRIS
    doc.add_page_break()


def contenido_previo(doc):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(2)
    r = p.add_run("Contenido")
    r.font.size = Pt(20)
    r.bold = True
    r.font.color.rgb = AZUL

    linea = doc.add_paragraph()
    linea.paragraph_format.space_after = Pt(10)
    borde_parrafo(linea, color="C6CDDA", tamano=8)

    campo_toc(doc)


def capitulo_1(doc):
    titulo(doc, "1. Qué te van a entregar y qué tienes que lograr", salto=True)
    parrafo(doc, "En la sustentación no vas a tener Packet Tracer ni la red ya armada. Te van a dar "
                 "**dos routers**, un **cable de consola** (adaptador USB–RS232) y **dos PC**. La red "
                 "que hay que levantar es la misma del diseño LAN–WAN–LAN: un PC crea la partida y hace "
                 "de servidor en una red local, el otro PC juega desde otra red local, y en el medio los "
                 "dos routers se encargan de que los paquetes lleguen.")
    parrafo(doc, "El objetivo no es solo que el juego abra: es que el tráfico **atraviese los dos routers**. "
                 "Eso se demuestra con un `ping` que llega con TTL 126 y con un `tracert` de tres saltos.")

    subtitulo(doc, "Qué debe quedar funcionando")
    vinetas(doc, [
        "**Cableado y consola:** los dos routers responden por el cable de consola.",
        "**Direccionamiento:** cada router tiene su LAN y el enlace WAN en 10.0.0.0/30.",
        "**Enrutamiento:** una ruta estática en cada router; sin NAT en el carril de Cisco IOS.",
        "**Conectividad:** PC2 hace ping a 192.168.1.10 y el TTL baja en 2.",
        "**Juego:** PC1 crea la partida y PC2 se une escribiendo la IP del servidor.",
        "**Evidencia:** capturas de `ipconfig`, `ping`, `tracert`, del panel F3 y del montaje.",
    ])

    aviso(doc, "No hace falta internet", "Los dos routers y los dos PC forman una red cerrada. El juego "
          "no usa servicios en la nube: todo el tráfico es local y el servidor es uno de los PC.", "info")

    subtitulo(doc, "Cómo está organizada la guía")
    parrafo(doc, "Los capítulos 2 a 4 son de mesa: qué llevar, cómo cablear y cómo entrar por consola. "
                 "Los capítulos 5 a 9 son de configuración y verificación. Los capítulos 10 a 12 son del "
                 "lado del juego y de los problemas típicos. El 13 es el guion de la exposición y el 14 "
                 "la lista de evidencias. Al final están la chuleta de comandos, la recuperación de "
                 "contraseña y una hoja de datos para llenar durante la prueba.")

    subtitulo(doc, "Tiempo esperado")
    tabla(doc,
          ["Momento", "Tiempo"],
          [["Cablear y encender", "5 min"],
           ["Configurar los dos routers", "8 min"],
           ["Verificar con ping y tracert", "3 min"],
           ["Abrir el juego y jugar", "4 min"]],
          anchos=[11.0, 4.0], tamano=9.5)

    aviso(doc, "Regla de oro", "Si algo no responde, no sigas agregando comandos: baja un nivel y "
          "comprueba la capa anterior (cable, IP del PC, gateway, ruta). La tabla del capítulo 12 está "
          "ordenada así.", "bien")


def capitulo_2(doc):
    titulo(doc, "2. La maleta: lo que hay que llevar")
    parrafo(doc, "Todo lo que sigue cabe en un morral. Lo importante es probar en casa lo que depende "
                 "de drivers, porque en la mesa no hay tiempo para instalarlos.")

    tabla(doc,
          ["☐", "Elemento", "Para qué"],
          [["☐", "2 PC con Godot 4.7 portable y el proyecto", "Servidor y cliente. Copiar también el ejecutable, no solo la carpeta del proyecto."],
           ["☐", "Adaptador USB–RS232 (DB9)", "Puente entre el PC y el cable de consola. Debe estar reconocido por Windows."],
           ["☐", "Cable de consola rollover", "Del adaptador al puerto CONSOLE del router. Suele ser azul claro."],
           ["☐", "3 cables de red Cat 5e o superior", "Dos para las LAN y uno para el enlace WAN. Llevar uno de repuesto."],
           ["☐", "Regleta o extensión", "Dos routers y dos PC necesitan cuatro tomas."],
           ["☐", "Esta guía impresa y la chuleta del anexo A", "Para no depender de otra pantalla."],
           ["☐", "Celular o cámara", "Fotos del montaje y de las pantallas para el informe."],
           ["☐", "Bolígrafo", "Para la hoja de datos del anexo C."]],
          anchos=[0.9, 6.2, 9.9], tamano=9)

    aviso(doc, "Prueba el adaptador antes", "Conéctalo a tu PC y abre el Administrador de dispositivos → "
          "Puertos (COM y LPT). Debe aparecer algo como «USB-SERIAL CH340 (COM3)». Si no aparece, instala "
          "el driver del chip (CH340, PL2303 o FTDI) y vuelve a probar.", "ojo")

    subtitulo(doc, "Software que ya debe estar listo")
    vinetas(doc, [
        "Godot 4.7 y el proyecto abierto al menos una vez en cada PC (así se genera la carpeta de importación).",
        "Un programa de terminal serial: **PuTTY** o **Tera Term**. PuTTY es un ejecutable suelto, no necesita instalación.",
        "La regla de firewall preparada en el PC servidor (capítulo 10).",
        "Las IP estáticas anotadas en un papel: PC1 192.168.1.10 y PC2 192.168.2.10.",
    ])


def capitulo_3(doc):
    titulo(doc, "3. El montaje, cable por cable")
    parrafo(doc, "La topología es sencilla porque solo hay dos PC: cada router hace de switch para su "
                 "propio PC y los routers se unen por un cable. No hacen falta switches externos.")
    figura(doc, "03-montaje.png", 1, "Montaje físico de la sustentación: dos PC, dos routers y el cable de consola.",
           ancho_cm=17.0)
    pasos(doc, [
        "Apaga los routers antes de cablear. Los PC pueden quedar encendidos.",
        "Conecta **PC1** a cualquier puerto **LAN** del Router A. Ese es el lado del servidor.",
        "Conecta **PC2** a cualquier puerto **LAN** del Router B. Ese es el lado de los clientes.",
        "Une los dos routers con un cable de red por los puertos que vas a usar como **WAN**. Si cada "
        "router tiene dos puertos, usa el que queda libre.",
        "Conecta el cable de consola: PC1 → adaptador USB–RS232 → cable rollover → puerto **CONSOLE** del Router A.",
        "Enciende primero los routers y espera uno o dos minutos a que terminen de arrancar. Después enciende "
        "o desbloquea los PC.",
    ])

    tabla(doc,
          ["Desde", "Hacia", "Cable"],
          [["PC1 (NIC)", "Puerto LAN del Router A", "Directo"],
           ["PC2 (NIC)", "Puerto LAN del Router B", "Directo"],
           ["Router A (puerto libre)", "Router B (puerto libre)", "Directo; los equipos modernos tienen auto-MDIX"],
           ["PC1 (USB)", "CONSOLE del Router A", "Consola: adaptador + rollover"]],
          anchos=[5.2, 6.0, 5.8], tamano=9)

    aviso(doc, "No es un cable de red", "El cable de consola no transporta tráfico del juego: solo sirve "
          "para escribirle comandos al router. Puedes tenerlo conectado mientras juegas sin que afecte.", "info")

    aviso(doc, "Cuidado con el puerto AUX", "Algunos routers tienen dos puertos parecidos: CONSOLE y AUX. "
          "La consola va siempre en CONSOLE. Si no sale texto, revisa primero eso.", "mal")

    subtitulo(doc, "Si el router solo tiene un puerto LAN y uno WAN")
    parrafo(doc, "Es el caso de los routers caseros, que además hacen NAT. El cableado físico es el mismo, "
                 "pero la configuración cambia: en vez de rutas estáticas se usa una redirección de puerto. "
                 "Ese es el **carril 2** del capítulo 11. No mezcles los dos estilos en el mismo montaje.")


def capitulo_4(doc):
    titulo(doc, "4. Entrar por consola: la terminal del router")
    parrafo(doc, "La consola es la puerta de entrada cuando el router no tiene pantalla ni teclado. "
                 "Windows ve el adaptador como un puerto serie (COM) y PuTTY se conecta a ese puerto.")

    subtitulo(doc, "Abrir la sesión")
    pasos(doc, [
        "Conecta el adaptador al PC y el cable rollover al puerto CONSOLE del router.",
        "Abre el Administrador de dispositivos y anota el número de COM del adaptador.",
        "Abre PuTTY. En **Session** elige **Serial** y escribe el COM (por ejemplo `COM3`).",
        "En **Connection → Serial** deja **9600** baudios, **8** bits de datos, **1** bit de parada, "
        "**paridad None** y **flow control None**.",
        "Pulsa **Open** y luego Enter dos o tres veces. Debe aparecer un prompt como `Router>`.",
    ])

    tabla(doc,
          ["Ajuste", "Valor"],
          [["Tipo de conexión", "Serial"],
           ["Puerto", "COM3 (el que muestre Windows)"],
           ["Velocidad", "9600"],
           ["Bits de datos / parada / paridad", "8 / 1 / None"],
           ["Control de flujo", "None"],
           ["Emulación", "VT100 o por defecto"]],
          anchos=[7.0, 9.0], tamano=9.5)

    subtitulo(doc, "Si no aparece nada")
    tabla(doc,
          ["Síntoma", "Qué revisar"],
          [["PuTTY abre pero la pantalla está vacía", "Pulsa Enter. Prueba otro COM y revisa que el cable esté en CONSOLE, no en AUX."],
           ["Windows no muestra ningún COM", "Falta el driver del adaptador o el cable USB está flojo."],
           ["Sale basura o caracteres raros", "Velocidad equivocada. Prueba 115200, que algunos equipos usan por defecto."],
           ["El router está apagado", "Enciéndelo y espera el arranque completo antes de escribir."],
           ["Aparece «Press RETURN to get started»", "Es normal: pulsa Enter y sigue."]],
          anchos=[6.7, 9.8], tamano=9)

    aviso(doc, "Atajo útil", "También puedes abrir la consola sin PuTTY desde PowerShell: "
          "`mode COM3:9600,n,8,1` y luego `putty -serial COM3`. Sirve para comprobar rápido que el puerto existe.", "bien")


def capitulo_5(doc):
    titulo(doc, "5. Primer contacto: mirar antes de tocar")
    parrafo(doc, "Cuando el router arranca por primera vez puede ofrecer un diálogo de configuración inicial. "
                 "Responde **no**: vamos a escribir los comandos a mano para que la configuración sea la misma "
                 "en los dos routers y se pueda explicar.")
    bloque_codigo(doc, """Would you like to enter the initial configuration dialog? [yes/no]: no

Router> enable
Router# show version
Router# show ip interface brief
Router# show cdp neighbors detail""")

    parrafo(doc, "Con esos tres comandos ya sabes casi todo lo que necesitas:")
    vinetas(doc, [
        "`show version` dice el modelo, la versión de IOS y cuánta memoria tiene. Anótalo para el informe.",
        "`show ip interface brief` lista las interfaces reales del equipo. Es la fuente de verdad para los nombres: "
        "puede ser `GigabitEthernet0/0`, `GigabitEthernet0/0/0`, `FastEthernet0/0` o una `Vlan1`.",
        "`show cdp neighbors detail` muestra el otro router si el cable WAN está bien puesto. Si no aparece, "
        "el problema es físico, no de configuración.",
    ])

    figura(doc, "05-decision-configuracion.png", 2,
           "Árbol de decisión: qué carril usar según lo que responda el router por consola.")

    subtitulo(doc, "Los dos carriles")
    tabla(doc,
          ["Señal en la consola", "Carril", "Qué se configura", "IP que escribe el cliente"],
          [["Responde a comandos IOS y `show version` funciona", "1 · Cisco IOS", "Interfaces y rutas estáticas, sin NAT", "192.168.1.10"],
           ["No hay CLI; solo página web de administración", "2 · Router con NAT", "WAN estática y redirección UDP 9999", "10.0.0.1"]],
          anchos=[6.6, 3.4, 4.4, 2.6], tamano=9)

    aviso(doc, "Router con switch integrado", "Si `show ip interface brief` muestra puertos "
          "`FastEthernet0/1/0` a `0/1/3` como switchport y una `Vlan1`, la IP de la LAN **no** va en el puerto "
          "físico: va en `interface Vlan1`. El puerto que va al otro router sí se configura como puerto ruteado.", "ojo")

    subtitulo(doc, "Si el router ya trae configuración de otra práctica")
    parrafo(doc, "Puede tener otro nombre, otras IP o una contraseña que nadie recuerda. Lo más limpio es "
                 "borrar la configuración de arranque y reiniciar:")
    bloque_codigo(doc, """enable
erase startup-config
reload
! Confirmar sin guardar cambios""")
    parrafo(doc, "Si pide contraseña y no la saben, el procedimiento de recuperación está en el anexo B. "
                 "Hazlo solo con permiso del profesor: implica reiniciar el equipo y cambiar el registro de arranque.")


def capitulo_6(doc):
    titulo(doc, "6. El direccionamiento: quién es quién")
    parrafo(doc, "El diseño usa dos redes locales /24 y un enlace WAN /30. La /30 es la red más pequeña que "
                 "da dos direcciones útiles, una para cada router, sin desperdiciar direcciones.")
    figura(doc, "04-topologia-logica.png", 3,
           "Direccionamiento y rutas del montaje real. El cliente escribe 192.168.1.10 y el paquete cruza los dos routers.",
           ancho_cm=17.0)

    tabla(doc,
          ["Dispositivo", "Interfaz", "Dirección", "Máscara", "Gateway"],
          [["PC1 (servidor)", "NIC", "192.168.1.10", "255.255.255.0", "192.168.1.1"],
           ["Router A", "LAN", "192.168.1.1", "255.255.255.0", "—"],
           ["Router A", "WAN", "10.0.0.1", "255.255.255.252", "—"],
           ["Router B", "WAN", "10.0.0.2", "255.255.255.252", "—"],
           ["Router B", "LAN", "192.168.2.1", "255.255.255.0", "—"],
           ["PC2 (cliente)", "NIC", "192.168.2.10", "255.255.255.0", "192.168.2.1"]],
          anchos=[3.8, 2.4, 3.4, 4.0, 2.9], tamano=9)

    subtitulo(doc, "Rutas estáticas")
    tabla(doc,
          ["Router", "Red destino", "Máscara", "Siguiente salto"],
          [["Router A", "192.168.2.0", "255.255.255.0", "10.0.0.2"],
           ["Router B", "192.168.1.0", "255.255.255.0", "10.0.0.1"]],
          anchos=[4.0, 4.8, 4.4, 3.3], tamano=9.5)

    parrafo(doc, "Cada router conoce sus dos redes conectadas y no sabe nada de la LAN del otro lado. La ruta "
                 "estática le dice: «para llegar a esa red, mándalo al router vecino». Con dos routers y un "
                 "solo camino posible, no hace falta OSPF.")

    subtitulo(doc, "Cómo se llaman las interfaces en tu router")
    tabla(doc,
          ["Si en `show ip interface brief` aparece…", "En los comandos escribe…"],
          [["GigabitEthernet0/0 y GigabitEthernet0/1", "`interface GigabitEthernet0/0`"],
           ["GigabitEthernet0/0/0 y GigabitEthernet0/0/1", "`interface GigabitEthernet0/0/0`"],
           ["FastEthernet0/0 y FastEthernet0/1", "`interface FastEthernet0/0`"],
           ["Vlan1 y FastEthernet0/1/0 a 0/1/3", "`interface Vlan1` para la LAN"],
           ["Serial0/0/0 (enlace serial)", "`interface Serial0/0/0`"]],
          anchos=[9.4, 7.1], tamano=9)

    aviso(doc, "Un detalle que confunde", "Los nombres son los del equipo, no los del diseño. En el diseño "
          "hablamos de «LAN» y «WAN»; en los comandos hay que escribir el nombre real que mostró el router.", "info")


def capitulo_7(doc):
    titulo(doc, "7. Router A, paso a paso")
    parrafo(doc, "Vas a configurar el router del lado del servidor. Los comandos se pueden pegar tal cual, "
                 "pero revisa primero el nombre real de las interfaces (capítulo 6).")

    subtitulo(doc, "7.1 Preparar el equipo")
    bloque_codigo(doc, """enable
configure terminal
hostname Router-A
no ip domain-lookup
enable secret clase-redes
!
line con 0
 logging synchronous
 exec-timeout 30 0
 exit""")

    tabla(doc,
          ["Comando", "Qué hace"],
          [["`enable`", "Entra al modo privilegiado (`#`)."],
           ["`configure terminal`", "Entra al modo de configuración global."],
           ["`hostname Router-A`", "Pone el nombre que aparece en el prompt y en `show cdp neighbors`."],
           ["`no ip domain-lookup`", "Evita que el router se quede esperando DNS cuando uno escribe mal un comando."],
           ["`enable secret clase-redes`", "Contraseña para el modo privilegiado. Cámbiala si el profesor lo pide."],
           ["`line con 0` / `logging synchronous`", "Hace que los mensajes del router no partan lo que estás escribiendo."],
           ["`exec-timeout 30 0`", "Cierra la sesión de consola tras 30 minutos sin actividad."]],
          anchos=[6.4, 10.1], tamano=9)

    subtitulo(doc, "7.2 Interfaces")
    bloque_codigo(doc, """interface GigabitEthernet0/0
 description LAN A - PC1
 ip address 192.168.1.1 255.255.255.0
 no shutdown
 exit
!
interface GigabitEthernet0/1
 description Enlace WAN hacia Router-B
 ip address 10.0.0.1 255.255.255.252
 no shutdown
 exit""")

    vinetas(doc, [
        "`description` es una etiqueta para leer la configuración después. Escríbela **sin tildes**.",
        "`ip address` asigna dirección y máscara. La LAN usa /24 y el enlace WAN /30.",
        "`no shutdown` enciende el puerto. Si se olvida, el puerto queda `administratively down` y nada pasa.",
    ])

    subtitulo(doc, "7.3 Ruta estática y guardado")
    bloque_codigo(doc, """ip route 192.168.2.0 255.255.255.0 10.0.0.2
end
write memory""")
    parrafo(doc, "La ruta dice: para llegar a la LAN B (192.168.2.0/24), entrega el paquete al Router B "
                 "(10.0.0.2). `write memory` guarda la configuración en la memoria permanente; si no lo haces, "
                 "al reiniciar el router se pierde todo.")

    subtitulo(doc, "7.4 Casos particulares")
    tabla(doc,
          ["Situación", "Qué cambiar"],
          [["El puerto LAN es switchport (`FastEthernet0/1/0` …)", "Configura la IP en `interface Vlan1` y deja el puerto del otro router como ruteado."],
           ["El enlace WAN es serial", "`interface Serial0/0/0`, `encapsulation hdlc` y `clock rate 64000` solo en el lado DCE (`show controllers serial 0/0/0`)."],
           ["El router solo tiene puertos FastEthernet", "Cambia el nombre de la interfaz; los demás comandos son iguales."],
           ["El router no acepta `enable secret`", "Puede ser otro sistema operativo: cambia al carril 2 del capítulo 11."]],
          anchos=[8.0, 8.5], tamano=9)

    subtitulo(doc, "7.5 Comprobar el Router A")
    bloque_codigo(doc, """show ip interface brief
show ip route""")
    parrafo(doc, "Debes ver las dos interfaces en `up`/`up` y, en la tabla de rutas, una línea que empieza "
                 "con **S** hacia 192.168.2.0/24 vía 10.0.0.2. Si la S no aparece, la ruta no se escribió o "
                 "la interfaz WAN está caída.")


def capitulo_8(doc):
    titulo(doc, "8. Router B, paso a paso")
    parrafo(doc, "Es el mismo procedimiento con las direcciones invertidas. Mueve el cable de consola del "
                 "Router A al Router B y conéctalo desde PC2 (o desde el PC que tengas a mano).")
    bloque_codigo(doc, """enable
configure terminal
hostname Router-B
no ip domain-lookup
enable secret clase-redes
!
line con 0
 logging synchronous
 exec-timeout 30 0
 exit
!
interface GigabitEthernet0/0
 description LAN B - PC2
 ip address 192.168.2.1 255.255.255.0
 no shutdown
 exit
!
interface GigabitEthernet0/1
 description Enlace WAN hacia Router-A
 ip address 10.0.0.2 255.255.255.252
 no shutdown
 exit
!
ip route 192.168.1.0 255.255.255.0 10.0.0.1
end
write memory""")

    aviso(doc, "Máscara del enlace WAN", "Los dos routers deben usar 255.255.255.252 en el enlace. Si uno "
          "queda en /24 y el otro en /30, se ven pero la ruta puede fallar. Es el error más común al copiar "
          "comandos de una práctica anterior.", "ojo")

    subtitulo(doc, "Comprobar el Router B")
    bloque_codigo(doc, """show ip interface brief
show ip route
ping 10.0.0.1""")
    parrafo(doc, "El ping a 10.0.0.1 prueba el enlace WAN antes de mirar las LAN. Si responde, el cable y las "
                 "dos direcciones WAN están bien.")


def capitulo_9(doc):
    titulo(doc, "9. Verificar antes de abrir el juego")
    parrafo(doc, "La verificación va de abajo hacia arriba: primero el cable y la IP del PC, después el "
                 "gateway, después el otro router y al final el servidor. Así, cuando algo falla, sabes "
                 "exactamente en qué capa quedarte.")

    tabla(doc,
          ["#", "Dónde", "Comando", "Resultado esperado"],
          [["1", "Router A y B", "`show ip interface brief`", "Todas las interfaces usadas en `up`/`up`"],
           ["2", "Router A y B", "`show ip route`", "Una ruta `S` hacia la LAN del otro lado"],
           ["3", "PC1", "`ping 192.168.1.1`", "Responde el gateway de la LAN A"],
           ["4", "PC2", "`ping 192.168.2.1`", "Responde el gateway de la LAN B"],
           ["5", "PC2", "`ping 10.0.0.1`", "Responde el Router A: el enlace WAN funciona"],
           ["6", "PC2", "`ping 192.168.1.10`", "Responde el servidor, con **TTL 126**"],
           ["7", "PC2", "`tracert 192.168.1.10`", "Tres saltos: 192.168.2.1, 10.0.0.1 y 192.168.1.10"],
           ["8", "PC1", "`ping 192.168.2.10`", "También responde en sentido contrario"]],
          anchos=[0.8, 2.6, 6.0, 7.1], tamano=9)

    subtitulo(doc, "Cómo se ve un ping correcto")
    bloque_codigo(doc, """C:\\>ping 192.168.1.10

Reply from 192.168.1.10: bytes=32 time=1ms TTL=126
Reply from 192.168.1.10: bytes=32 time<1ms TTL=126
Reply from 192.168.1.10: bytes=32 time<1ms TTL=126
Reply from 192.168.1.10: bytes=32 time<1ms TTL=126""")

    parrafo(doc, "El **TTL 126** es la prueba de que el paquete pasó por dos routers: Windows envía con TTL "
                 "128 y cada router resta uno. Si llega 127, solo cruzó uno; si llega 128, llegó directo.")

    subtitulo(doc, "Cómo se ve un tracert correcto")
    bloque_codigo(doc, """C:\\>tracert 192.168.1.10

  1    <1 ms    <1 ms    <1 ms    192.168.2.1
  2    <1 ms    <1 ms    <1 ms    10.0.0.1
  3    <1 ms    <1 ms    <1 ms    192.168.1.10
Trace complete.""")

    aviso(doc, "El primer ping puede perder paquetes", "Al principio los equipos están resolviendo ARP. "
          "Si el primero falla, repite el ping antes de sospechar de la configuración.", "bien")

    aviso(doc, "Si el ping responde pero el juego no conecta", "La red está bien: el problema está en el "
          "firewall del servidor, en el puerto o en la IP que se escribió en el menú. Ve al capítulo 12.", "ojo")


def capitulo_10(doc):
    titulo(doc, "10. Los PC y el juego")
    parrafo(doc, "Con la red verificada, el juego solo necesita tres cosas: IP correcta en cada PC, una "
                 "regla de firewall en el servidor y la IP correcta escrita en el menú.")

    subtitulo(doc, "10.1 IP estática")
    parrafo(doc, "En Windows: Configuración → Red e Internet → Ethernet → Propiedades de la red → "
                 "Asignación de IP → Editar → Manual → IPv4. Escribe los valores de la tabla y deja el DNS "
                 "vacío o con 8.8.8.8 (no se usa, pero algunos sistemas se quejan si está vacío).")
    tabla(doc,
          ["PC", "IP", "Máscara", "Puerta de enlace"],
          [["PC1", "192.168.1.10", "255.255.255.0", "192.168.1.1"],
           ["PC2", "192.168.2.10", "255.255.255.0", "192.168.2.1"]],
          anchos=[2.2, 4.6, 5.0, 5.2], tamano=9.5)
    parrafo(doc, "Comprueba con `ipconfig` que no haya dos adaptadores con IP y que la Wi-Fi esté **desconectada** "
                 "o sin ruta predeterminada. Una Wi-Fi encendida puede mandar el tráfico por el camino equivocado.")

    subtitulo(doc, "10.2 Firewall del servidor")
    parrafo(doc, "Solo en PC1. Abre PowerShell **como administrador** y ejecuta:")
    bloque_codigo(doc, """netsh advfirewall firewall add rule name="LAN Shooter UDP 9999" dir=in action=allow protocol=UDP localport=9999""")
    parrafo(doc, "La regla se puede quitar al terminar:")
    bloque_codigo(doc, """netsh advfirewall firewall delete rule name="LAN Shooter UDP 9999\"""")
    aviso(doc, "Perfil de red", "Si Windows marca la red como «Pública», la regla puede no aplicarse. "
          "En ese caso cambia el perfil a «Privada» en la configuración de la red.", "ojo")

    subtitulo(doc, "10.3 Crear la partida en PC1")
    pasos(doc, [
        "Abre el proyecto en Godot 4.7 y pulsa **F5**. La escena inicial es el menú.",
        "Escribe el nombre del jugador.",
        "Pulsa **Crear partida (Host)**. El menú muestra la IP local del equipo (192.168.1.10).",
        "Espera en la sala; el host también juega, no es un servidor dedicado.",
    ])

    subtitulo(doc, "10.4 Unirse desde PC2")
    pasos(doc, [
        "Abre el juego y escribe el nombre del jugador.",
        "En **IP del servidor** escribe `192.168.1.10`.",
        "En **Puerto** deja `9999`.",
        "Pulsa **Unirse**. Debe entrar a la sala de espera.",
        "El host pulsa **Iniciar partida** cuando estén todos.",
    ])
    parrafo(doc, "Si usaste el carril 2 (routers con NAT), la IP que se escribe es **10.0.0.1**, no la IP "
                 "privada del servidor.")

    figura(doc, "juego-cliente.png", 4,
           "Panel de red (F3) en el cliente: rol, servidor, jugadores, ping, tráfico y estado del simulador.")

    subtitulo(doc, "10.5 El panel de red")
    parrafo(doc, "F3 abre el panel de red. En el cliente muestra el rol, el servidor al que se conectó, "
                 "la cantidad de jugadores, el RTT (ping), los paquetes enviados y recibidos y el estado del "
                 "simulador de mala red. Con el panel abierto, F4 agrega retraso y F5 pérdida de paquetes; "
                 "solo funcionan en el cliente. Es la mejor evidencia de que el tráfico está cruzando la red.")


def capitulo_11(doc):
    titulo(doc, "11. Carril 2: routers con NAT y redirección de puerto")
    parrafo(doc, "Usa este carril solo si los routers no tienen consola con comandos IOS y se administran por "
                 "página web. Sucede con routers caseros o de operador: siempre hacen NAT en el puerto WAN y "
                 "no se puede apagar.")
    aviso(doc, "No mezcles los carriles", "Si los routers son Cisco, haz todo con el carril 1. Si son "
          "caseros, haz todo con el carril 2. Cambiar de carril a mitad del montaje solo genera dudas.", "mal")

    subtitulo(doc, "11.1 Cableado")
    pasos(doc, [
        "Une los dos routers por sus puertos **WAN** con un cable de red.",
        "Conecta PC1 a un puerto **LAN** del Router A y PC2 a un puerto **LAN** del Router B.",
        "Entra a la página de administración de cada router (suele ser 192.168.0.1 o la IP que indique la etiqueta).",
    ])

    subtitulo(doc, "11.2 Direccionamiento")
    tabla(doc,
          ["Ajuste", "Router A", "Router B"],
          [["IP de la LAN", "192.168.1.1", "192.168.2.1"],
           ["WAN: tipo", "IP estática", "IP estática"],
           ["WAN: IP", "10.0.0.1", "10.0.0.2"],
           ["WAN: máscara", "255.255.255.252", "255.255.255.252"],
           ["WAN: puerta de enlace", "10.0.0.2", "10.0.0.1"],
           ["DHCP", "Apagado o reservado para el PC", "Apagado o reservado para el PC"]],
          anchos=[5.4, 5.8, 5.8], tamano=9)

    subtitulo(doc, "11.3 Redirección del puerto en Router A")
    parrafo(doc, "En Router A busca **Port Forwarding**, **Virtual Server** o **Redirección de puertos** y crea:")
    tabla(doc,
          ["Campo", "Valor"],
          [["Puerto externo / servicio", "9999"],
           ["Protocolo", "UDP"],
           ["IP interna", "192.168.1.10"],
           ["Puerto interno", "9999"],
           ["Estado", "Activado"]],
          anchos=[7.0, 9.0], tamano=9)

    parrafo(doc, "En el juego, PC2 escribe **10.0.0.1** y puerto **9999**. El paquete llega al router y él lo "
                 "entrega a PC1. La respuesta sale de vuelta por la misma redirección.")

    aviso(doc, "El ping al servidor no responde en este carril", "Es normal: el NAT oculta la LAN A. "
          "La prueba correcta es `ping 10.0.0.1` desde PC2, y luego el juego. No pierdas tiempo intentando "
          "hacer ping a 192.168.1.10.", "ojo")

    subtitulo(doc, "11.4 Qué sirve como evidencia")
    vinetas(doc, [
        "`ping 10.0.0.1` desde PC2: prueba el enlace WAN.",
        "`tracert 10.0.0.1`: muestra el primer salto (Router B) y el segundo (Router A).",
        "El panel F3 del cliente: RTT y paquetes, que es la prueba real de que el juego atraviesa los routers.",
        "La tabla de redirección de puertos del Router A, en una captura de la página de administración.",
    ])


def capitulo_12(doc):
    titulo(doc, "12. Si algo falla: tabla de diagnóstico")
    parrafo(doc, "Busca el síntoma en la primera columna y revisa en orden. Casi todos los problemas de la "
                 "sustentación están en esta tabla.")
    tabla(doc,
          ["Síntoma", "Causa probable", "Qué hacer"],
          [["Por consola no aparece nada", "COM equivocado, driver ausente, cable en AUX o router apagado",
            "Revisar el capítulo 4; probar otro COM y otro cable."],
           ["Pide contraseña y no la saben", "Configuración de otra práctica", "Recuperación del anexo B o pedir al profesor un equipo limpio."],
           ["`% Invalid input detected`", "Se escribió un comando en el modo equivocado o con otro nombre de interfaz",
            "Mirar el prompt (`>`, `#`, `(config)#`) y usar `show ip interface brief`."],
           ["La interfaz queda `administratively down`", "Falta `no shutdown`", "Entrar a la interfaz y ejecutar `no shutdown`."],
           ["La interfaz queda `down/down`", "Cable, puerto o equipo del otro lado apagado", "Probar otro cable y otro puerto; revisar el otro router."],
           ["El ping al gateway propio falla", "IP o máscara del PC, cable o puerto LAN", "Revisar `ipconfig` y el cableado del PC."],
           ["El ping al otro router falla", "WAN mal direccionada o cable entre routers", "Comparar las dos IP WAN y la máscara /30."],
           ["El ping al servidor falla pero el gateway responde", "Falta la ruta estática en alguno de los dos routers",
            "`show ip route` en ambos; debe aparecer la `S`."],
           ["El TTL llega 127 o 128", "El paquete no cruzó los dos routers", "Revisar el montaje: puede haber un cable directo entre PC."],
           ["El juego se queda en «Conectando a…»", "Firewall del servidor, IP mal escrita o puerto distinto",
            "Regla UDP 9999, IP 192.168.1.10 y puerto 9999."],
           ["El juego conecta pero se pierde", "Wi-Fi activa o cable en mal estado", "Apagar Wi-Fi y revisar el cable; usar F4/F5 para comparar."],
           ["El cliente entra pero no ve jugadores", "El host no inició la partida o el cliente entró a otra IP",
            "Revisar el panel F3: servidor y jugadores."],
           ["En el carril 2 el ping a 10.0.0.1 funciona pero el juego no", "Falta la redirección UDP 9999 o apunta a otra IP",
            "Revisar el puerto, el protocolo y la IP interna del servidor."],
           ["Windows no deja crear la regla de firewall", "PowerShell sin permisos de administrador", "Abrir como administrador."]],
          anchos=[5.6, 6.0, 5.4], tamano=8.8)

    aviso(doc, "Orden de diagnóstico", "Cable → IP del PC → gateway → enlace WAN → ruta estática → firewall → "
          "juego. No saltes pasos: cada uno supone que el anterior funciona.", "bien")


def capitulo_13(doc):
    titulo(doc, "13. El guion de la sustentación")
    parrafo(doc, "Con la red funcionando, la exposición se trata de contar lo mismo que muestra la guía, "
                 "pero en voz alta y sin prisa. Este es un reparto posible para tres integrantes.")
    tabla(doc,
          ["Momento", "Qué se hace", "Quién"],
          [["0–1 min", "Presentar el proyecto y dibujar la topología: dos LAN, dos routers, una WAN.", "Integrante 1"],
           ["1–2 min", "Mostrar el montaje físico y el cable de consola. Explicar por qué /30 en la WAN.", "Integrante 2"],
           ["2–3 min", "Abrir la consola, `show version` y `show ip interface brief`.", "Integrante 2"],
           ["3–6 min", "Configurar Router A y Router B, narrando cada bloque: LAN, WAN, ruta estática.", "Integrante 3"],
           ["6–8 min", "Ping y tracert desde PC2. Señalar el TTL 126 y los tres saltos.", "Integrante 1"],
           ["8–10 min", "Crear la partida, unirse, jugar y abrir F3. Cerrar con la conclusión.", "Integrante 3"]],
          anchos=[2.4, 11.2, 3.4], tamano=9)

    subtitulo(doc, "Frases que conviene tener listas")
    vinetas(doc, [
        "«Cada router solo conoce las redes que tiene conectadas; por eso hace falta una ruta estática.»",
        "«El TTL llega en 126 porque salió en 128 y cada router restó uno.»",
        "«El servidor es uno de los jugadores: no hay servidor dedicado, el host también juega.»",
        "«El input viaja no fiable a 60 por segundo; los eventos importantes van fiables.»",
        "«El puerto 9999 es UDP porque un disparo no se puede quedar esperando un reenvío.»",
    ])

    subtitulo(doc, "Ensayar dos veces")
    parrafo(doc, "La primera vez que se configura un router ajeno siempre sale algo: una interfaz con otro "
                 "nombre, un cable flojo, un COM distinto. Ensayar con la guía impresa hace que esos tropiezos "
                 "ocurran antes de la nota, no durante.")

    aviso(doc, "No narrar la configuración línea por línea", "Mientras se escribe, conviene explicar qué se "
          "busca, no leer los comandos. El jurado ya los ve en la pantalla.", "info")


def capitulo_14(doc):
    titulo(doc, "14. Evidencias y datos para el informe")
    parrafo(doc, "El informe tiene una sección pendiente de la prueba con equipos físicos. Estas capturas y "
                 "datos alcanzan para completarla.")

    tabla(doc,
          ["#", "Dónde", "Qué capturar"],
          [["1", "PC2, consola", "`ipconfig` con IP y puerta de enlace del cliente"],
           ["2", "PC2, consola", "`ping 192.168.1.10` con TTL 126 y 0 % de pérdida"],
           ["3", "PC2, consola", "`tracert 192.168.1.10` con los tres saltos"],
           ["4", "Router A y B", "`show ip interface brief` y `show ip route`"],
           ["5", "PC1, juego", "Partida con F3 abierto: rol host, dos jugadores y ping"],
           ["6", "PC2, juego", "Partida con F3 abierto: rol cliente, RTT y tráfico"],
           ["7", "Montaje", "Foto de los dos PC, los dos routers y el cable de consola"],
           ["8", "Router A", "Etiqueta o `show version` con el modelo y la versión de IOS"]],
          anchos=[0.8, 3.4, 12.8], tamano=9)

    subtitulo(doc, "Qué escribir en el informe")
    vinetas(doc, [
        "Modelo de los dos routers y versión de IOS.",
        "IP y puerto usados por el cliente, y por qué esa IP (carril 1 o carril 2).",
        "RTT medido en el panel F3 y pérdida observada en el enlace local.",
        "Resultado de ping y tracert, con el TTL.",
        "Una frase que explique por qué la ruta estática resuelve el problema con dos routers.",
    ])

    aviso(doc, "La hoja de datos", "El anexo C tiene una tabla en blanco para llenar en la mesa. Pásala al "
          "informe el mismo día: al día siguiente los detalles se olvidan.", "bien")


def capitulo_15(doc):
    titulo(doc, "15. Desmontaje y limpieza")
    parrafo(doc, "Antes de devolver los equipos, déjalos como estaban. Es parte de la prueba y evita que el "
                 "siguiente grupo encuentre contraseñas ajenas.")
    pasos(doc, [
        "En cada router, por consola: `enable`, `erase startup-config`, `reload` y confirma sin guardar.",
        "Si el router trae switch integrado, borra también la base de VLAN: `delete vlan.dat` y reinicia.",
        "En PC1, elimina la regla de firewall con el comando del capítulo 10.",
        "Devuelve las IP de los PC a DHCP (Editar → Automático).",
        "Apaga y desconecta en orden inverso al montaje: PC, routers, cables.",
        "Guarda las fotos y las capturas en la carpeta del proyecto antes de borrar nada.",
    ])
    aviso(doc, "Contraseñas", "Si dejaste `enable secret clase-redes`, bórralo con `no enable secret` antes "
          "de entregar el equipo, o borra toda la configuración como indica el paso 1.", "ojo")


def anexo_a(doc):
    titulo(doc, "Anexo A. Chuleta de comandos", salto=True)
    parrafo(doc, "Una página para tener al lado. Sustituye los nombres de interfaz por los de tu router "
                 "(capítulo 6) antes de pegar.")

    subtitulo(doc, "Router A (servidor)")
    bloque_codigo(doc, """enable
configure terminal
hostname Router-A
no ip domain-lookup
enable secret clase-redes
line con 0
 logging synchronous
 exit
interface GigabitEthernet0/0
 description LAN A - PC1
 ip address 192.168.1.1 255.255.255.0
 no shutdown
 exit
interface GigabitEthernet0/1
 description Enlace WAN hacia Router-B
 ip address 10.0.0.1 255.255.255.252
 no shutdown
 exit
ip route 192.168.2.0 255.255.255.0 10.0.0.2
end
write memory""", ancho=17.0)

    subtitulo(doc, "Router B (clientes)")
    bloque_codigo(doc, """enable
configure terminal
hostname Router-B
no ip domain-lookup
enable secret clase-redes
line con 0
 logging synchronous
 exit
interface GigabitEthernet0/0
 description LAN B - PC2
 ip address 192.168.2.1 255.255.255.0
 no shutdown
 exit
interface GigabitEthernet0/1
 description Enlace WAN hacia Router-A
 ip address 10.0.0.2 255.255.255.252
 no shutdown
 exit
ip route 192.168.1.0 255.255.255.0 10.0.0.1
end
write memory""", ancho=17.0)

    subtitulo(doc, "Verificación rápida")
    tabla(doc,
          ["Dónde", "Comando", "Buscar"],
          [["Router", "`show ip interface brief`", "up / up"],
           ["Router", "`show ip route`", "S 192.168.x.0/24"],
           ["PC2", "`ping 10.0.0.1`", "Responde"],
           ["PC2", "`ping 192.168.1.10`", "TTL 126"],
           ["PC2", "`tracert 192.168.1.10`", "3 saltos"],
           ["PC1", "`ipconfig`", "IP .10 y gateway .1"]],
          anchos=[2.4, 7.6, 7.0], tamano=9)


def anexo_b(doc):
    titulo(doc, "Anexo B. Recuperación de contraseña")
    parrafo(doc, "Solo si el router pide una contraseña que nadie conoce y el profesor autoriza. El "
                 "procedimiento reinicia el equipo y arranca sin la configuración guardada.")
    pasos(doc, [
        "Conecta la consola y abre PuTTY a 9600 8-N-1.",
        "Apaga el router y enciéndelo. Durante los primeros segundos envía una pausa: en PuTTY, "
        "**Special Command → Break** (o Ctrl+Pausa).",
        "Debe aparecer el prompt `rommon 1>`.",
        "Escribe `confreg 0x2142` y luego `reset`. El router arranca sin usar la configuración guardada.",
        "Responde `no` al diálogo inicial. Escribe `enable` (no pedirá contraseña).",
        "Recupera la configuración anterior con `copy startup-config running-config`.",
        "Vuelve a dejar el registro normal con `config-register 0x2102`, cambia la contraseña si hace falta y "
        "guarda con `write memory`.",
    ])
    aviso(doc, "Advertencia", "Este procedimiento deja la configuración anterior cargada pero con las "
          "contraseñas visibles. Al terminar, guarda y revisa que el router arranque normal. Si el equipo no "
          "es Cisco, el procedimiento es distinto: pide ayuda al profesor.", "mal")


def anexo_c(doc):
    titulo(doc, "Anexo C. Hoja de datos de la prueba", salto=True)
    parrafo(doc, "Llénala durante la sustentación y pásala al informe. Es la forma más rápida de no olvidar "
                 "ningún dato.")
    filas = [
        ["Modelo del Router A", "", ""],
        ["Modelo del Router B", "", ""],
        ["Versión de IOS", "", ""],
        ["Puerto LAN usado en A", "", ""],
        ["Puerto WAN usado en A", "", ""],
        ["Puerto LAN usado en B", "", ""],
        ["Puerto WAN usado en B", "", ""],
        ["IP de PC1 / PC2", "", ""],
        ["Ping PC2 → 192.168.1.10 (TTL)", "", ""],
        ["tracert (saltos)", "", ""],
        ["RTT en F3 (cliente)", "", ""],
        ["Pérdida con F5 (si se probó)", "", ""],
        ["Carril usado (1 IOS / 2 NAT)", "", ""],
        ["Hora de inicio y fin", "", ""],
        ["Observaciones", "", ""],
    ]
    tabla(doc, ["Dato", "Valor", "Notas"], filas, anchos=[6.8, 5.2, 5.0], tamano=9, primera_columna_bold=True)

    subtitulo(doc, "Capturas tomadas")
    filas_capturas = [[f"☐ {n}", "", ""] for n in [
        "ipconfig del cliente", "ping con TTL 126", "tracert de tres saltos",
        "show ip interface brief", "show ip route", "F3 del host", "F3 del cliente", "Foto del montaje",
    ]]
    tabla(doc, ["Captura", "Archivo", "Observaciones"], filas_capturas, anchos=[5.6, 5.6, 5.8], tamano=9)


def cierre(doc):
    titulo(doc, "Documentación relacionada")
    parrafo(doc, "Todo lo que hay en esta guía sale de los documentos del proyecto. Si necesitas el detalle "
                 "técnico, está ahí.")
    tabla(doc,
          ["Archivo", "Qué contiene"],
          [["`docs/red.md`", "Diseño LAN–WAN–LAN: topología, direccionamiento, rutas y mensajes del juego."],
           ["`docs/prueba-real.md`", "Prueba con equipos reales y los dos casos de router (IOS y NAT)."],
           ["`docs/simulacion-packet-tracer.md`", "Simulación en Packet Tracer, comandos y verificación."],
           ["`docs/diagramas/red/`", "Topologías física y lógica en draw.io."],
           ["`docs/diagramas/estados/`", "Estados de la conexión y árbol de decisión de configuración."],
           ["`docs/sustentacion.html`", "Guion hablado de la exposición, en lenguaje sencillo."],
           ["`README.md`", "Cómo ejecutar el juego y controles."]],
          anchos=[6.2, 10.3], tamano=9)

    figura(doc, "topologia-packet-tracer.png", 5,
           "Diseño de referencia en Packet Tracer: dos switches y cuatro clientes. En la mesa se usan dos PC "
           "y el router hace de switch.", fuente="Fuente: docs/simulacion-packet-tracer.md")

    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(10)
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    rich(p, "Con dos routers, dos PC y una ruta estática por lado, el juego cruza la red. "
            "El resto es explicarlo con calma.", tamano=10, color=GRIS, cursiva=True)


def construir():
    doc = Document()
    preparar_estilos(doc)
    configurar_pagina(doc)
    actualizar_campos(doc)

    portada(doc)
    contenido_previo(doc)

    capitulo_1(doc)
    capitulo_2(doc)
    capitulo_3(doc)
    capitulo_4(doc)
    capitulo_5(doc)
    capitulo_6(doc)
    capitulo_7(doc)
    capitulo_8(doc)
    capitulo_9(doc)
    capitulo_10(doc)
    capitulo_11(doc)
    capitulo_12(doc)
    capitulo_13(doc)
    capitulo_14(doc)
    capitulo_15(doc)
    anexo_a(doc)
    anexo_b(doc)
    anexo_c(doc)
    cierre(doc)

    SALIDA.parent.mkdir(parents=True, exist_ok=True)
    doc.save(SALIDA)
    print(f"Generado: {SALIDA}")


if __name__ == "__main__":
    construir()
