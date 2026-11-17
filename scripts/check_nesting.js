const fs = require('fs');
const file = process.argv[2];
const code = fs.readFileSync(file, 'utf-8');

// Strip comments
const lines = code.split(/\r?\n/).map(l => {
  const trimmed = l.trim();
  if (trimmed.startsWith('*')) return '';
  const quoteIdx = l.indexOf('"');
  if (quoteIdx >= 0) return l.substring(0, quoteIdx);
  return l;
});

// Tokenize by statement period
const text = lines.join(' ');
// Split by space/tokens
const tokens = text.match(/[A-Za-z0-9_#\-]+|\.|\(|\)/g) || [];

let ifs = 0;
let loops = 0;
let cases = 0;
let trys = 0;

for (let i = 0; i < tokens.length; i++) {
  const tok = tokens[i].toUpperCase();
  const prev = i > 0 ? tokens[i - 1].toUpperCase() : '';
  
  if (tok === 'IF' && prev !== 'ENDIF') ifs++;
  if (tok === 'ENDIF') ifs--;
  if (tok === 'LOOP' && prev !== 'ENDLOOP') loops++;
  if (tok === 'ENDLOOP') loops--;
  if (tok === 'CASE' && prev !== 'ENDCASE') cases++;
  if (tok === 'ENDCASE') cases--;
  if (tok === 'TRY' && prev !== 'ENDTRY') trys++;
  if (tok === 'ENDTRY') trys--;
}

console.log(`Token-based check for ${file}:`);
console.log(`IF balance: ${ifs}`);
console.log(`LOOP balance: ${loops}`);
console.log(`CASE balance: ${cases}`);
console.log(`TRY balance: ${trys}`);
