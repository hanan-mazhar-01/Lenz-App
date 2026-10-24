/* Shared helpers for the Lenz mock-ups: stroke icons + the animated mascot built from assets/lenz/character. */
const LM = (() => {
  const ICONS = {
    home: '<path d="M3 11l9-8 9 8v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    heart: '<path d="M12 20s-7-4.5-9-9a5 5 0 0 1 9-3 5 5 0 0 1 9 3c-2 4.5-9 9-9 9z"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7"/>',
    scan: '<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"/><circle cx="12" cy="12" r="3.2"/>',
    camera: '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
    x: '<path d="M6 6l12 12M18 6L6 18"/>',
    bolt: '<path d="M13 3L5 14h6l-1 7 8-11h-6z"/>',
    image: '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="8.5" cy="10" r="1.5"/><path d="M21 16l-5-5-8 8"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M19 5l-1.5 1.5M6.5 17.5L5 19"/>',
    focus: '<circle cx="12" cy="12" r="7.5"/><circle cx="12" cy="12" r="2"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/>',
    glare: '<path d="M3 3l18 18M10.6 6.2A9 9 0 0 1 12 6c5 0 8 4 9 6a14 14 0 0 1-2.6 3.4M6.5 7.6C4.4 9 3.2 11 3 12c1 2 4 6 9 6 1.4 0 2.6-.3 3.7-.8"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8v.01"/>',
    crown: '<path d="M3 8l4.5 4L12 5l4.5 7L21 8l-2 11H5z"/>',
    check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    sparkle: '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/>',
    shield: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M8.5 12l2.5 2.5L15.5 10"/>',
    layers: '<path d="M12 3l9 5-9 5-9-5z"/><path d="M3 13l9 5 9-5"/>',
    infinity: '<path d="M7 8a4 4 0 1 0 0 8c4 0 6-8 10-8a4 4 0 1 1 0 8c-4 0-6-8-10-8z"/>',
    chevron: '<path d="M6 9l6 6 6-6"/>',
    flip: '<path d="M4 8h12l-3-3M20 16H8l3 3"/>',
  };
  const ic = (name, size = 24, sw = 2) =>
    `<svg class="ic" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round">${ICONS[name]}</svg>`;

  // Layer placement in the shared 1254x1254 rig space (assets/lenz/character/meta.json).
  const L = {
    head: [325, 18, 684, 677], irisL: [545, 430, 145, 150], irisR: [804, 378, 123, 148],
    browL: [542, 318, 87, 52], browR: [785, 261, 70, 32], lidL: [518, 414, 174, 176], lidR: [804, 354, 155, 179],
    body: [391, 674, 561, 565], tail: [107, 738, 493, 457], mag: [848, 537, 264, 340],
  };
  const OPEN_L = 'M617 421 L600 421 L582 425 L562 435 L539 458 L529 477 L525 491 L525 511 L529 531 L541 553 L564 572 L595 582 L618 581 L635 577 L660 564 L668 557 L670 551 L677 544 L684 518 L683 488 L677 467 L671 456 L660 442 L645 430Z';
  const OPEN_R = 'M874 361 L861 364 L847 371 L827 390 L815 414 L811 434 L811 452 L818 480 L827 496 L839 509 L861 522 L874 525 L888 525 L912 517 L935 496 L948 468 L951 452 L951 434 L944 406 L935 390 L924 378 L906 366 L888 361Z';
  const VIEWS = { full: [40, -150, 1180, 1400], bust: [250, -20, 900, 860], peek: [300, 10, 720, 700] };
  let uid = 0;
  const img = (n, extra = '') => {
    const [x, y, w, h] = L[n];
    return `<image href="../assets/lenz/character/${n}.png" x="${x}" y="${y}" width="${w}" height="${h}" ${extra}/>`;
  };
  /** Returns the mascot as an inline SVG string. view: full | bust | peek. */
  function mascot(view = 'bust', { still = false } = {}) {
    const id = ++uid, vb = VIEWS[view].join(' ');
    return `<svg class="lenz ${view === 'bust' ? 'lz-fade' : ''}" viewBox="${vb}" preserveAspectRatio="xMidYMid meet" ${still ? 'style="--x:0"' : ''}>
      <defs><clipPath id="cl${id}"><path d="${OPEN_L}"/></clipPath><clipPath id="cr${id}"><path d="${OPEN_R}"/></clipPath></defs>
      <g class="lz-char">
        <g class="lz-tail">${img('tail')}</g>${img('body')}
        <g class="lz-head">${img('head')}${img('browL')}${img('browR')}
          <g clip-path="url(#cl${id})"><g transform="translate(-6 -1.5)">${img('irisL')}</g>${img('lidL', 'class="lz-lid"')}</g>
          <g clip-path="url(#cr${id})"><g transform="translate(6.5 -.5)">${img('irisR')}</g>${img('lidR', 'class="lz-lid"')}</g>
        </g>
        <g class="lz-mag">${img('mag')}</g>
      </g></svg>`;
  }
  /** Fills every [data-lenz="bust|peek|full"] element with the mascot. */
  function mount(root = document) {
    root.querySelectorAll('[data-lenz]').forEach((el) => { el.innerHTML = mascot(el.dataset.lenz); });
    root.querySelectorAll('[data-ic]').forEach((el) => {
      el.innerHTML = ic(el.dataset.ic, +el.dataset.size || 24, +el.dataset.sw || 2);
    });
  }
  return { ic, mascot, mount };
})();
