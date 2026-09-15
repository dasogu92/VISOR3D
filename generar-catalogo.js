#!/usr/bin/env node
/**
 * generar-catalogo.js
 *
 * Recorre la carpeta de modelos y reescribe catalogo.json con lo que hay
 * realmente en disco. Conserva el nombre de los modelos que ya estaban en
 * el catálogo anterior; a los nuevos les pone el nombre de la carpeta.
 *
 * Uso, desde la carpeta que contiene index.html:
 *   node generar-catalogo.js
 *   node generar-catalogo.js --dir models --out catalogo.json
 */

const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const opt = (flag, def) => {
  const i = args.indexOf(flag);
  return i >= 0 && args[i + 1] ? args[i + 1] : def;
};

const DIR = opt('--dir', 'models');
const OUT = opt('--out', 'catalogo.json');

const EXT_MODELO = { '.js': 'legacy', '.json': 'legacy', '.glb': 'glb', '.gltf': 'glb' };

if (!fs.existsSync(DIR)) {
  console.error(`No existe la carpeta "${DIR}". Usa --dir para indicar otra.`);
  process.exit(1);
}

// Nombres del catálogo anterior, para no perderlos
const previos = new Map();
if (fs.existsSync(OUT)) {
  try {
    const raw = JSON.parse(fs.readFileSync(OUT, 'utf8'));
    (raw.modelos || raw.models || raw || []).forEach(r => {
      if (r.codigo) previos.set(r.codigo, r);
    });
  } catch (e) {
    console.warn(`Aviso: ${OUT} no se ha podido leer, se generará de cero.`);
  }
}

function modeloEn(dirAbs) {
  const files = fs.readdirSync(dirAbs).filter(f =>
    fs.statSync(path.join(dirAbs, f)).isFile()
  );
  // El GLB manda sobre el legacy si conviven los dos
  const glb = files.find(f => ['.glb', '.gltf'].includes(path.extname(f).toLowerCase()));
  if (glb) return { archivo: glb, formato: 'glb' };
  const legacy = files.find(f => ['.js', '.json'].includes(path.extname(f).toLowerCase()));
  if (legacy) return { archivo: legacy, formato: 'legacy' };
  return null;
}

const modelos = [];
const sinModelo = [];

for (const entrada of fs.readdirSync(DIR).sort()) {
  const abs = path.join(DIR, entrada);
  const st = fs.statSync(abs);

  if (st.isDirectory()) {
    const hit = modeloEn(abs);
    if (!hit) { sinModelo.push(entrada); continue; }
    const codigo = entrada;
    const prev = previos.get(codigo);
    modelos.push({
      codigo,
      nombre: prev ? prev.nombre : entrada,
      carpeta: codigo,
      formato: hit.formato
    });
  } else {
    // Archivos sueltos: models/0100.js
    const ext = path.extname(entrada).toLowerCase();
    if (!EXT_MODELO[ext]) continue;
    const codigo = path.basename(entrada, ext);
    const prev = previos.get(codigo);
    modelos.push({
      codigo,
      nombre: prev ? prev.nombre : codigo,
      carpeta: codigo,
      formato: EXT_MODELO[ext]
    });
  }
}

fs.writeFileSync(OUT, JSON.stringify({ modelos }, null, 2), 'utf8');

const nuevos = modelos.filter(m => !previos.has(m.codigo));
const perdidos = [...previos.keys()].filter(c => !modelos.some(m => m.codigo === c));

console.log(`${OUT} escrito con ${modelos.length} modelos.`);
console.log(`  legacy: ${modelos.filter(m => m.formato === 'legacy').length}`);
console.log(`  glb:    ${modelos.filter(m => m.formato === 'glb').length}`);
if (nuevos.length)     console.log(`  nuevos: ${nuevos.map(m => m.codigo).join(', ')}`);
if (perdidos.length)   console.log(`  ya no están en la carpeta: ${perdidos.join(', ')}`);
if (sinModelo.length)  console.log(`  carpetas sin modelo dentro: ${sinModelo.join(', ')}`);
