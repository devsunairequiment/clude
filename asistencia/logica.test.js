// Ejecutar: node logica.test.js  (necesita el paquete xlsx accesible desde Node)
const assert = require('assert');
const X = require('xlsx');
const A = require('./logica.js');

// Libro de prueba: dos alumnos de brigadas distintas, sin fechas aún.
const libro = A.leer(A.plantilla());
assert.deepStrictEqual(libro.headers, ['Comando', 'Brigada', 'Matrícula', 'Nombre', 'Total']);
assert.strictEqual(libro.filas.length, 1);
libro.filas.push({ Comando: 'Comando 1', Brigada: 'Brigada B', 'Matrícula': '002', Nombre: 'Otro', Total: '' });

// Fechas: se insertan en orden cronológico, antes de Total, y repetir no duplica.
A.asegurarFecha(libro, '02/11/2026');
A.asegurarFecha(libro, '20/10/2026');
A.asegurarFecha(libro, '20/10/2026');
assert.deepStrictEqual(libro.headers, ['Comando', 'Brigada', 'Matrícula', 'Nombre', '20/10/2026', '02/11/2026', 'Total']);

// Marcar y desmarcar.
A.marcar(libro.filas[0], '20/10/2026', true);
A.marcar(libro.filas[1], '20/10/2026', true);
A.marcar(libro.filas[1], '20/10/2026', false);
assert.deepStrictEqual(A.presentes(libro, '20/10/2026', 'Comando 1', 'Brigada A'), { presentes: 1, total: 1 });
assert.deepStrictEqual(A.presentes(libro, '20/10/2026', 'Comando 1', ''), { presentes: 1, total: 2 });

// Guardar y releer: la marca sobrevive y el Total es una fórmula COUNTIF.
const bytes = A.aBytes(libro);
const wb = X.read(bytes, { type: 'array' });
const ws = wb.Sheets[wb.SheetNames[0]];
const filaA = libro.filas.findIndex(f => f.Brigada === 'Brigada A') + 2;
assert.strictEqual(ws[`E${filaA}`].v, A.MARCA);
assert.strictEqual(ws[`G${filaA}`].f, `COUNTIF(E${filaA}:F${filaA},"${A.MARCA}")`);

const releido = A.leer(bytes);
assert.strictEqual(releido.filas.find(f => f.Brigada === 'Brigada A')['20/10/2026'], A.MARCA);
assert.strictEqual(releido.filas.find(f => f.Brigada === 'Brigada B')['20/10/2026'], '');

// Excel convierte "20/10/2026" en fecha real: al leer, el encabezado vuelve a dd/mm/aaaa.
const hojaFecha = X.utils.aoa_to_sheet([['Comando', 'Brigada', 'Matrícula', 'Nombre', 46315, 'Total'], ['C', 'B', 7, 'Ana', '✔', '']]);
const wbFecha = X.utils.book_new();
X.utils.book_append_sheet(wbFecha, hojaFecha, 'Asistencia');
const fechaLeida = A.leer(X.write(wbFecha, { type: 'array', bookType: 'xlsx' }));
assert.deepStrictEqual(fechaLeida.headers.slice(4, 5), ['20/10/2026']);
assert.strictEqual(fechaLeida.filas[0]['Matrícula'], '7');

console.log('OK: todas las pruebas de logica.js pasaron');
