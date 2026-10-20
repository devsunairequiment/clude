// Une index.html con inicial.js y logica.js en un solo archivo: node build.js
const fs = require('fs');
let html = fs.readFileSync('index.html', 'utf8');
for (const archivo of ['inicial.js', 'logica.js']) {
  const etiqueta = `<script src="${archivo}"></script>`;
  if (!html.includes(etiqueta)) throw new Error('no encuentro ' + etiqueta);
  html = html.replace(etiqueta, () => `<script>\n${fs.readFileSync(archivo, 'utf8')}</script>`);
}
fs.writeFileSync('asistencia-movil.html', html);
console.log('asistencia-movil.html generado');
