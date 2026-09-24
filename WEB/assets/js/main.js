// Hashline landing page: scroll-driven efekty bez knihoven.
// Každá sekce s [data-track] dostane --p (0–1) podle toho, kolik z ní uživatel prošel,
// prvky s [data-view] dostanou --v (0–1) podle průchodu viewportem.
// Při prefers-reduced-motion se nic nepřipíná a obsah je rovnou celý vidět (viz CSS).
(() => {
  "use strict";

  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  // Rozdělí text odstavce na slova (zachová <mark> a nedělitelné mezery).
  const splitWords = (el) => {
    const walk = (node) => {
      for (const child of Array.from(node.childNodes)) {
        if (child.nodeType === Node.TEXT_NODE) {
          const frag = document.createDocumentFragment();
          child.textContent.split(/(\s+)/).forEach((part) => {
            if (!part) return;
            if (/^\s+$/.test(part)) { frag.append(part); return; }
            const span = document.createElement("span");
            span.className = "w";
            span.textContent = part;
            frag.append(span);
          });
          child.replaceWith(frag);
        } else if (child.nodeType === Node.ELEMENT_NODE) {
          walk(child);
        }
      }
    };
    walk(el);
    return $$(".w", el);
  };

  const nav = document.querySelector("[data-nav]");
  const hero = document.querySelector(".hero");
  const tracks = $$("[data-track]");
  const views = $$("[data-view]");

  const demo = document.querySelector("[data-demo]");
  const win = demo?.querySelector(".win");
  const lines = demo ? $$(".ln", demo) : [];
  const blocks = demo ? $$(".pv__b", demo) : [];
  const steps = demo ? $$(".step", demo) : [];

  const truth = document.querySelector("[data-reveal]");
  const words = truth ? splitWords(truth.querySelector("[data-words]")) : [];

  const plan = document.querySelector("[data-hscroll]");
  const planTrack = plan?.querySelector(".plan__track");
  let planDistance = 0;

  const layout = () => {
    if (!plan || !planTrack) return;
    if (reduce.matches) { plan.style.removeProperty("--plan-h"); planDistance = 0; return; }
    planDistance = Math.max(0, planTrack.scrollWidth - window.innerWidth);
    plan.style.setProperty("--plan-h", `${window.innerHeight + planDistance}px`);
  };

  const progressOf = (el) => {
    const r = el.getBoundingClientRect();
    const run = r.height - window.innerHeight;
    return run > 0 ? clamp(-r.top / run) : clamp(-r.top / Math.max(1, r.height));
  };

  let lastStep = -1;
  const updateDemo = (p) => {
    // 0–0.2 okno se narovná, 0.18–0.72 píše se, 0.82+ náhled se schová
    const typed = Math.floor(clamp((p - 0.18) / 0.54) * lines.length);
    lines.forEach((ln, i) => {
      ln.classList.toggle("on", i < typed);
      ln.classList.toggle("caret", i === Math.min(typed, lines.length - 1) && p < 0.82);
    });
    blocks.forEach((b) => b.classList.toggle("on", Number(b.dataset.at) < typed));
    win?.classList.toggle("is-solo", p > 0.82);

    const step = p < 0.42 ? 0 : p < 0.78 ? 1 : 2;
    if (step !== lastStep) {
      steps.forEach((s, i) => s.classList.toggle("is-on", i === step));
      lastStep = step;
    }
  };

  const updateWords = (p) => {
    const lit = Math.round(clamp((p - 0.08) / 0.75) * words.length);
    words.forEach((w, i) => w.classList.toggle("lit", i < lit));
  };

  let ticking = false;
  const frame = () => {
    ticking = false;
    const vh = window.innerHeight;

    for (const el of tracks) {
      const p = progressOf(el);
      el.style.setProperty("--p", p.toFixed(4));
      if (el === demo) updateDemo(p);
      else if (el === truth) updateWords(p);
      else if (el === plan && planTrack) planTrack.style.setProperty("--x", (p * planDistance).toFixed(1));
    }

    for (const el of views) {
      const r = el.getBoundingClientRect();
      // 0 když horní hrana vstupuje zdola, 1 když je prvek ve 40 % výšky okna
      const v = clamp((vh - r.top) / (vh * 0.6));
      el.style.setProperty("--v", v.toFixed(3));
      if (v > 0.35 && !el.dataset.counted) countUp(el);
    }

    // Navigace ztmavne ve chvíli, kdy hero přechází do tmavé (závoj od --p 0,55).
    if (nav && hero) nav.dataset.theme = progressOf(hero) > 0.62 ? "dark" : "light";
  };
  const onScroll = () => {
    if (reduce.matches) return;
    if (!ticking) { ticking = true; requestAnimationFrame(frame); }
  };

  // Počítadlo u čísel v sekci Rychlost, jednou při prvním zobrazení.
  const countUp = (el) => {
    el.dataset.counted = "1";
    const target = el.querySelector("[data-count]");
    if (!target) return;
    const end = Number(target.dataset.count);
    const decimals = Number(target.dataset.decimals || 0);
    const fmt = (n) => n.toFixed(decimals).replace(".", ",");
    const t0 = performance.now();
    const dur = 1100;
    const tick = (t) => {
      const k = clamp((t - t0) / dur);
      const eased = 1 - Math.pow(1 - k, 3);
      target.textContent = fmt(end * eased);
      if (k < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  };

  const start = () => {
    if (reduce.matches) {
      tracks.forEach((el) => el.style.removeProperty("--p"));
      views.forEach((el) => { el.style.setProperty("--v", "1"); el.dataset.counted = "1"; });
      lines.forEach((l) => l.classList.add("on"));
      blocks.forEach((b) => b.classList.add("on"));
      words.forEach((w) => w.classList.add("lit"));
      steps.forEach((s) => s.classList.add("is-on"));
      window.removeEventListener("scroll", onScroll);
      layout();
      if (nav) nav.dataset.theme = window.scrollY > (hero?.offsetHeight ?? 0) * 0.6 ? "dark" : "light";
      window.addEventListener("scroll", () => {
        if (nav) nav.dataset.theme = window.scrollY > (hero?.offsetHeight ?? 0) * 0.6 ? "dark" : "light";
      }, { passive: true });
      return;
    }
    layout();
    frame();
    window.addEventListener("scroll", onScroll, { passive: true });
  };

  window.addEventListener("resize", () => { layout(); onScroll(); }, { passive: true });
  reduce.addEventListener?.("change", () => window.location.reload());
  document.fonts?.ready.then(() => { layout(); onScroll(); });
  start();
})();
