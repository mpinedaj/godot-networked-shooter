# Guía de configuración para la sustentación

Este directorio contiene las fuentes del documento
[`../guia-routers-sustentacion.docx`](../guia-routers-sustentacion.docx), que se
entrega solo en `.docx`.

| Archivo | Qué es |
|---|---|
| `construir_guia.py` | Genera el `.docx` completo con `python-docx`. Todo el texto y el diseño están aquí. |
| `figuras/` | Figuras exportadas desde los `.drawio` de [`../diagramas/`](../diagramas/). |
| `exportar-figuras.ps1` | Vuelve a exportar las figuras con draw.io de escritorio. |

## Regenerar el documento

1. Instalar las dependencias:

   ```
   python -m pip install python-docx pillow
   ```

2. Generar el `.docx`:

   ```
   python docs/guia/construir_guia.py
   ```

3. Abrir el documento en Word. El índice se genera al abrir; si queda vacío,
   clic derecho sobre él → **Actualizar campo** (o F9).

El índice es de un solo nivel (capítulos y anexos) para que quepa en una página.
Las figuras se reducen a 1400 px de ancho antes de incrustarlas: con los PNG de
2× de draw.io, Word tarda varios minutos en exportar el documento.

## Regenerar las figuras

Los diagramas se editan en [`../diagramas/`](../diagramas/) y se exportan a PNG
con draw.io de escritorio. El script recibe la ruta de `draw.io.exe`:

```powershell
.\docs\guia\exportar-figuras.ps1 -Drawio "C:\ruta\a\draw.io.exe"
```

El `.docx` guarda las figuras ya incrustadas, así que solo hace falta repetir
este paso si cambia un diagrama. `figuras/05-decision-configuracion.png`
proviene de [`../diagramas/estados/02-decision-configuracion.drawio`](../diagramas/estados/02-decision-configuracion.drawio).
