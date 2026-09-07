// Decode presentation only: no terminal control sequence is ever executed.
const palette = ['#BAC4BE','#F28B82','#A8D5A2','#F5CE7A','#8AB4F8','#D9AEF0','#8EDAD5','#E8EEE9', '#AAB5AE','#FFA39B','#C3E8B7','#FFE29B','#ACCAFF','#ECC5FF','#BAEFED','#FFFFFF'];
function indexed(n) {
  if (n < 16) return palette[n];
  if (n < 232) { n -= 16; return '#' + [Math.floor(n / 36), Math.floor(n / 6) % 6, n % 6].map(x => (x ? x * 40 + 55 : 0).toString(16).padStart(2, '0')).join(''); }
  return '#' + (8 + (n - 232) * 10).toString(16).padStart(2, '0').repeat(3);
}
export function terminalDocument(ansi) {
  const runs = []; let style = {}; let link; let offset = 0;
  const append = text => { if (text) runs.push({ text, ...style, ...(link ? { link } : {}) }); };
  const escapes = /\x1b\[([0-?]*)([ -/]*)([@-~])|\x1b\]([^\x07\x1b]*)(?:\x07|\x1b\\)|\x1b[^\[]/g;
  for (const match of ansi.matchAll(escapes)) {
    append(ansi.slice(offset, match.index)); offset = match.index + match[0].length;
    if (match[3] === 'm') {
      const values = (match[1] || '0').split(';').map(Number);
      for (let i = 0; i < values.length; i++) {
        const value = values[i];
        if (value === 0) style = {};
        else if (value === 1) style.bold = true;
        else if (value === 2) style.dim = true;
        else if (value === 3) style.italic = true;
        else if (value === 4) style.underline = true;
        else if (value === 22) { delete style.bold; delete style.dim; }
        else if (value === 23) delete style.italic;
        else if (value === 24) delete style.underline;
        else if (value === 39) delete style.color;
        else if (value >= 30 && value <= 37) style.color = palette[value - 30];
        else if (value >= 90 && value <= 97) style.color = palette[value - 90 + 8];
        else if (value === 38 || value === 48) {
          let color;
          if (values[i + 1] === 5 && values[i + 2] >= 0 && values[i + 2] <= 255) { color = indexed(values[i + 2]); i += 2; }
          else if (values[i + 1] === 2 && values.slice(i + 2, i + 5).length === 3 && values.slice(i + 2, i + 5).every(v => v >= 0 && v <= 255)) { color = '#' + values.slice(i + 2, i + 5).map(v => v.toString(16).padStart(2, '0')).join(''); i += 4; }
          if (value === 38 && color) style.color = color;
        }
      }
    } else if (match[4]?.startsWith('8;')) {
      const destination = match[4].split(';').slice(2).join(';');
      try { const url = new URL(destination); link = ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password ? url.href : undefined; } catch { link = undefined; }
    }
  }
  append(ansi.slice(offset));
  for (const run of runs) run.text = run.text.replace(/[\x00-\x08\x0B-\x1F\x7F]/g, '');
  return { text: runs.map(r => r.text).join(''), runs };
}
