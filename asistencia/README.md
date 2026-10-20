# Asistencia (móvil + Excel)

Una sola página para el teléfono. El Excel es la base de datos: la app marca el ✔ en la fila del alumno y la fecha del día.

## Uso

1. Abre `asistencia-movil.html` en el teléfono (Chrome o Edge). Necesita internet la primera vez para cargar SheetJS.
2. Primera vez: **Descargar plantilla**, llénala en la computadora y luego **Abrir mi Excel**. O abre directamente tu Excel con el formato de abajo.
3. Elige **comando**, **brigada** y **fecha**. Toca a un alumno para marcar asistencia; toca otra vez para desmarcar.
4. Lo que marcas se guarda en el teléfono al instante. Cuando termines, **Descargar Excel**. El Excel original no cambia hasta que lo descargas.

## Formato del Excel (primera hoja)

| Comando | Brigada | Matrícula | Nombre | 20/10/2026 | 27/10/2026 | … | Total |
|---|---|---|---|---|---|---|---|

- Las cuatro primeras columnas van siempre al inicio, en ese orden. Puedes tener más columnas (por ejemplo Teléfono); se conservan.
- Cada columna de fecha es texto `dd/mm/aaaa`. La app crea la del día cuando la abres.
- `Total` es una fórmula `COUNTIF` por alumno. Excel la recalcula al abrir el archivo.

## Reglas que aplica la app

- Cada alumno tiene una sola brigada, y cada brigada un solo comando.
- Una fecha = una columna. Las columnas quedan en orden cronológico y `Total` siempre al final.
- Marcar o desmarcar es un toque. No se duplican fechas ni marcas.
- El Excel queda ordenado por comando, brigada y nombre al guardarlo.
- La app no sobrescribe tu archivo: descargas una copia nueva.

## Pruebas y build

```
npm install xlsx
NODE_PATH=$PWD/node_modules node logica.test.js
```

`asistencia-movil.html` se genera uniendo `index.html` con `logica.js` (el script de `logica.js` va en lugar de `<script src="logica.js">`).

## Límites conocidos

- La marca es el texto `✔`, no una casilla de formulario de Excel: la librería no escribe casillas reales.
- Los datos viven en el navegador del teléfono. Si borras los datos del sitio o cambias de teléfono, descarga el Excel antes.
- Las fechas deben escribirse `dd/mm/aaaa` en el encabezado. Excel a veces las convierte en fecha; la app lo reconoce.
