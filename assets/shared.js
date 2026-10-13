/* White Lotus Florist: shared config, data access and bouquet previews */
window.WL = (function () {
  const SUPABASE_URL = 'https://ujuqxkietsbmmmvezijk.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_HWQi5byQ-iIpossL2dzl8A_v3eSixA3'; // public key; data is protected by database rules
  const H = { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' };

  async function rpc(fn, args) {
    const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/' + fn, { method: 'POST', headers: H, body: JSON.stringify(args || {}) });
    const text = await r.text();
    let body = null; try { body = text ? JSON.parse(text) : null; } catch (e) { body = text; }
    if (!r.ok) throw new Error((body && body.message) || 'Something went wrong. Check your connection and try again.');
    return body;
  }
  async function select(table, query) {
    const r = await fetch(SUPABASE_URL + '/rest/v1/' + table + '?' + query, { headers: H });
    if (!r.ok) throw new Error('Could not load ' + table + '.');
    return r.json();
  }

  const COLORS = { Red:'#C0283A', Burgundy:'#6D1F33', Pink:'#E5809F', Blush:'#F1C3C6', Peach:'#F2A98A', Orange:'#E8782A', Yellow:'#F2C230', White:'#F5F2EC', Cream:'#EFE3C8', Lavender:'#B7A3D6', Purple:'#7C4B9E', Blue:'#5C7FC4', Green:'#6F9455', Mixed:'#D98FB0' };

  function esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c])); }
  function money(n) { n = Number(n) || 0; return '$' + (Number.isInteger(n) ? n : n.toFixed(2)); }

  /* Placeholder bloom for a flower with no photo yet */
  const ph = {};
  function placeholder(f) {
    const key = (f.color || 'Pink') + (f.id || f.name);
    if (ph[key]) return ph[key];
    const c = document.createElement('canvas'); c.width = c.height = 200; const x = c.getContext('2d');
    x.fillStyle = '#2C4A30'; x.fillRect(0, 0, 200, 200);
    const hex = COLORS[f.color] || '#E5809F';
    x.translate(100, 100);
    [[10, 52, 30, 46], [8, 32, 24, 34], [6, 14, 16, 22]].forEach(([n, d, rx, ry], k) => {
      for (let i = 0; i < n; i++) { x.save(); x.rotate(i / n * Math.PI * 2 + k * .3); x.translate(0, -d); x.globalAlpha = .92; x.fillStyle = hex; x.beginPath(); x.ellipse(0, 0, rx * .6, ry * .6, 0, 0, 7); x.fill(); x.restore(); }
    });
    x.globalAlpha = 1; x.fillStyle = 'rgba(0,0,0,.25)'; x.beginPath(); x.arc(0, 0, 9, 0, 7); x.fill();
    return ph[key] = c.toDataURL('image/jpeg', .8);
  }
  function photo(f) { return f.photo || placeholder(f); }

  /* Same stem split the database uses: stems shared evenly, remainder to the first picks */
  function recipe(style, flowers) {
    const n = flowers.length; if (!n) return { items: [], total: 0 };
    const per = Math.floor(style.stems / n), extra = style.stems % n;
    let sum = 0;
    const items = flowers.map((f, i) => { const q = per + (i < extra ? 1 : 0); sum += q * Number(f.price); return { f, stems: q }; }).filter(x => x.stems > 0);
    return { items, total: Math.ceil(sum + Number(style.fee)) };
  }

  /* Bouquet preview: the customer's own flower photos arranged in the style's shape */
  const LAYOUTS = {
    posy: { slots: [[50,40,30],[31,33,24],[69,33,24],[36,55,23],[64,55,23],[50,20,22],[50,61,20]], base: 'posy' },
    handtied: { slots: [[50,36,26],[32,28,22],[68,28,22],[40,14,19],[60,14,19],[24,44,19],[76,44,19],[41,49,21],[59,49,21],[50,20,18]], base: 'handtied' },
    vase: { slots: [[50,34,24],[32,30,21],[68,30,21],[40,15,18],[60,15,18],[20,42,18],[80,42,18],[36,47,19],[64,47,19],[50,19,17],[26,24,16],[74,24,16],[50,50,18]], base: 'vase' }
  };
  const BASES = {
    posy: '<svg class="base" viewBox="0 0 100 125" preserveAspectRatio="none" aria-hidden="true"><path d="M30 66 L50 112 L70 66 Z" fill="var(--paper)"/><path d="M26 64 Q50 78 74 64 L70 70 Q50 82 30 70 Z" fill="var(--paper-edge)"/><path d="M44 96 l12 0 l-2 6 l-8 0z" fill="var(--ribbon)"/></svg>',
    handtied: '<svg class="base" viewBox="0 0 100 125" preserveAspectRatio="none" aria-hidden="true"><path d="M12 50 L50 122 L88 50 Q50 64 12 50 Z" fill="var(--paper)"/><path d="M12 50 L36 96 L50 122 L30 60 Z" fill="var(--paper-edge)" opacity=".7"/><path d="M38 92 q12 -4 24 0 l-2 7 q-10 -3 -20 0 z" fill="var(--ribbon)"/><path d="M50 95 q-14 6 -16 18 M50 95 q14 6 16 18" stroke="var(--ribbon)" stroke-width="2.4" fill="none" stroke-linecap="round"/></svg>',
    vase: '<svg class="base" viewBox="0 0 100 125" preserveAspectRatio="none" aria-hidden="true"><path d="M30 60 Q24 92 34 120 L66 120 Q76 92 70 60 Z" fill="var(--glass)" stroke="var(--glass-edge)" stroke-width="1.2"/><path d="M33 84 Q31 102 36 118 L64 118 Q69 102 67 84 Z" fill="var(--water)"/><path d="M38 66 Q35 90 39 112" stroke="var(--glass-edge)" stroke-width="1.6" fill="none" opacity=".7"/></svg>'
  };
  const GREENS = {
    posy: [[24,52,-30],[76,52,30],[50,64,0]],
    handtied: [[16,30,-50],[84,30,50],[28,8,-20],[72,8,20],[50,4,0]],
    vase: [[12,30,-55],[88,30,55],[22,6,-25],[78,6,25],[50,2,0]]
  };
  function preview(kind, items) {
    const L = LAYOUTS[kind] || LAYOUTS.posy;
    const slots = L.slots, total = items.reduce((t, x) => t + x.stems, 0) || 1;
    // give each flower a share of the visible blooms proportional to its stems, at least one each
    const counts = items.map(x => Math.max(1, Math.round(x.stems / total * slots.length)));
    while (counts.reduce((a, b) => a + b, 0) > slots.length) { const i = counts.indexOf(Math.max(...counts)); counts[i]--; }
    while (counts.reduce((a, b) => a + b, 0) < slots.length) { const i = counts.indexOf(Math.min(...counts)); counts[i]++; }
    const seq = []; let k = 0;
    while (seq.length < slots.length) { for (let i = 0; i < items.length; i++) if (counts[i] > 0) { seq.push(items[i].f); counts[i]--; } if (++k > 99) break; }
    let leaves = '';
    (GREENS[kind] || []).forEach(([x, y, r]) => { leaves += '<i class="leaf" style="left:' + x + '%;top:' + (y * .8) + '%;transform:translate(-50%,-50%) rotate(' + r + 'deg)"></i>'; });
    let blooms = '';
    for (let i = seq.length - 1; i >= 0; i--) {
      const [x, y, s] = slots[i];
      blooms += '<span class="bloom" style="left:' + (x - s / 2) + '%;top:' + (y * .8 - s * .4) + '%;width:' + s + '%"><img alt="" src="' + photo(seq[i]) + '"></span>';
    }
    return '<div class="preview ' + kind + '" role="img" aria-label="Preview of the bouquet">' + BASES[L.base] + leaves + blooms + '</div>';
  }

  return { rpc, select, COLORS, esc, money, photo, recipe, preview };
})();
