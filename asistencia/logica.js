// Lógica del libro de asistencia, sin pantalla: se prueba en Node y se usa en el navegador.
// Libro = { headers: [...], filas: [{ columna: valor }] }. Columnas: Comando, Brigada, Matrícula, Nombre, fechas dd/mm/aaaa..., Total.
var Asistencia = (function () {
  const X = typeof XLSX !== 'undefined' ? XLSX : require('xlsx');
  const BASE = ['Comando', 'Brigada', 'Matrícula', 'Nombre'];
  const TOTAL = 'Total';
  // shortcut: la marca es el texto ✔ y no una casilla de formulario de Excel (SheetJS no las escribe), subir a casilla real con un editor de .xlsx que las soporte
  const MARCA = '✔';
  const FALTA = '✗';
  const esFecha = h => /^\d{2}\/\d{2}\/\d{4}$/.test(h);
  const aOrden = f => f.slice(6) + f.slice(3, 5) + f.slice(0, 2); // dd/mm/aaaa -> aaaammdd

  // Excel convierte "20/10/2026" en fecha real al escribirlo en el encabezado: vuelve a texto dd/mm/aaaa.
  function encabezado(h) {
    if (typeof h !== 'number') return String(h).trim();
    const f = X.SSF.parse_date_code(h);
    return `${String(f.d).padStart(2, '0')}/${String(f.m).padStart(2, '0')}/${f.y}`;
  }

  // Columnas base primero, luego las extra del usuario, luego fechas en orden y Total al final.
  function ordenarColumnas(headers) {
    const fechas = headers.filter(esFecha).sort((a, b) => aOrden(a).localeCompare(aOrden(b)));
    return [...headers.filter(h => !esFecha(h) && h !== TOTAL), ...fechas, TOTAL];
  }

  function leer(bytes) {
    const wb = X.read(bytes, { type: 'array' });
    const aoa = X.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, defval: '' });
    const headers = ordenarColumnas(aoa[0].map(encabezado));
    if (BASE.some((h, i) => headers[i] !== h)) throw new Error('El Excel debe tener estas columnas al inicio: ' + BASE.join(', '));
    const filas = aoa.slice(1).filter(r => r.some(v => v !== '')).map(r => {
      const f = {};
      headers.forEach((h, i) => { f[h] = BASE.includes(h) ? String(r[i]).trim() : r[i]; });
      return f;
    });
    return { headers, filas };
  }

  // Inserta la columna de la fecha en orden cronológico, antes de Total.
  function asegurarFecha(libro, fecha) {
    if (libro.headers.includes(fecha)) return;
    libro.headers = ordenarColumnas([...libro.headers, fecha]);
    libro.filas.forEach(f => { f[fecha] = ''; });
  }

  // valor: MARCA (asistió), FALTA (no asistió) o '' (sin marcar).
  function marcar(fila, fecha, valor) {
    fila[fecha] = valor;
  }

  function contar(fila, fechas) {
    return fechas.filter(d => fila[d] === MARCA).length;
  }

  // Ordena por comando, brigada y nombre, para que la hoja quede clasificada.
  function ordenar(libro) {
    libro.filas.sort((a, b) => a.Comando.localeCompare(b.Comando, 'es') ||
      a.Brigada.localeCompare(b.Brigada, 'es') || a.Nombre.localeCompare(b.Nombre, 'es'));
  }

  // Total por alumno como fórmula, así Excel lo recalcula si editas a mano.
  function aBytes(libro) {
    ordenar(libro);
    const ws = X.utils.json_to_sheet(libro.filas, { header: libro.headers });
    const fechas = libro.headers.filter(esFecha);
    const colTotal = libro.headers.length - 1;
    const colIni = libro.headers.findIndex(esFecha);
    libro.filas.forEach((f, i) => {
      const dir = X.utils.encode_cell({ r: i + 1, c: colTotal });
      const v = contar(f, fechas); // valor en caché, para vistas previas sin recalcular
      ws[dir] = { t: 'n', v };
      if (fechas.length) ws[dir].f = `COUNTIF(${X.utils.encode_col(colIni)}${i + 2}:${X.utils.encode_col(colTotal - 1)}${i + 2},"${MARCA}")`;
    });
    const wb = X.utils.book_new();
    X.utils.book_append_sheet(wb, ws, 'Asistencia');
    return X.write(wb, { type: 'array', bookType: 'xlsx' });
  }

  // Plantilla con un alumno de ejemplo para que veas el formato.
  function plantilla() {
    const libro = { headers: [...BASE, TOTAL], filas: [{ Comando: 'Comando 1', Brigada: 'Brigada A', 'Matrícula': '001', Nombre: 'Alumno ejemplo', Total: '' }] };
    return aBytes(libro);
  }

  // Texto con tabulaciones: se pega directo en Excel. El Total va calculado.
  function aTexto(libro) {
    ordenar(libro);
    const fechas = libro.headers.filter(esFecha);
    const celda = (f, h) => (h === TOTAL ? contar(f, fechas) : f[h] ?? '');
    return [libro.headers, ...libro.filas.map(f => libro.headers.map(h => celda(f, h)))]
      .map(r => r.join('\t')).join('\n');
  }

  function presentes(libro, fecha, comando, brigada) {
    const filas = libro.filas.filter(f => (!comando || f.Comando === comando) && (!brigada || f.Brigada === brigada));
    return { presentes: filas.filter(f => f[fecha] === MARCA).length, total: filas.length };
  }

  return { MARCA, FALTA, BASE, TOTAL, leer, asegurarFecha, marcar, aBytes, aTexto, plantilla, presentes, esFecha, ordenarColumnas };
})();

if (typeof module !== 'undefined') module.exports = Asistencia;
