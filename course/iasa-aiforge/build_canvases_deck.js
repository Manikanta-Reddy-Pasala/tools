// IASA canvases explained with AIForge: how canvases help, the canvas map,
// then each canvas drawn in its own shape and filled in for AIForge.
const pptxgen = require("pptxgenjs");
const { applyTheme } = require(process.env.SKILL + "/apply_theme.js");

const THEME = {
  name: "Plain",
  headFontFace: "Calibri",
  bodyFontFace: "Calibri",
  colors: {
    dk1: "222222", lt1: "FFFFFF", dk2: "404040", lt2: "F2F2F2",
    accent1: "1F4E79", accent2: "FFF2CC", accent3: "D9D9D9", accent4: "C55A11",
    accent5: "548235", accent6: "7F7F7F", hlink: "1F4E79", folHlink: "404040",
  },
};
const HEX = THEME.colors;
const TINT = { orange: "FBE5D6", green: "E2F0D9", teal: "DEEAF6" };
const LINE = "A6A6A6";
const TOTAL = 14;

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.33 x 7.5
pres.title = "IASA canvases, explained with AIForge";
pres.author = "Manikanta Reddy Pasala";
pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
const C = pres.SchemeColor;
const SH = pres.shapes;

// ---------- layouts ----------
pres.defineSlideMaster({
  title: "DARK",
  background: { color: C.background1 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.8, y: 2.2, w: 11.7, h: 1.2, fontSize: 40, bold: true, color: C.text1, valign: "bottom", align: "left", margin: 0 }, text: "" } },
    { placeholder: { options: { name: "body", type: "body", x: 0.8, y: 3.55, w: 11.0, h: 1.0, fontSize: 22, color: C.accent6, valign: "top", align: "left", margin: 0 }, text: "" } },
  ],
});
pres.defineSlideMaster({
  title: "CONTENT",
  background: { color: C.background1 },
  margin: [0.5, 0.6, 0.6, 0.6],
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.6, y: 0.4, w: 9.6, h: 0.8, fontSize: 32, bold: true, color: C.text1, valign: "middle", align: "left", margin: 0 }, text: "" } },
    { placeholder: { options: { name: "body", type: "body", x: 0.6, y: 1.2, w: 9.6, h: 0.5, fontSize: 18, color: C.text1, valign: "top", align: "left", margin: 0 }, text: "" } },
    { text: { text: "IASA canvases  ·  explained with AIForge", options: { x: 0.6, y: 7.05, w: 6, h: 0.3, fontSize: 10, color: C.accent6, margin: 0 } } },
  ],
  slideNumber: { x: 12.3, y: 7.05, w: 0.5, h: 0.3, fontSize: 10, color: C.accent6, align: "right" },
});

// ---------- helpers ----------
function txt(s, text, o) { s.addText(text, Object.assign({ isTextBox: true, margin: 0, valign: "top", color: C.text1, fontSize: 14 }, o)); }
function lines(items, opt) { return items.map((t, i) => ({ text: t, options: Object.assign({ breakLine: i < items.length - 1 }, opt || {}) })); }
function content(section, title, sub) {
  const s = pres.addSlide({ masterName: "CONTENT", sectionTitle: section });
  s.addText(title, { placeholder: "title" });
  if (sub) s.addText(sub, { placeholder: "body" });
  return s;
}
// plain label, top right
function sticky(s, small, big) {
  txt(s, `${small}  ·  ${big}`, { x: 9.3, y: 0.55, w: 3.43, h: 0.3, fontSize: 12, color: C.accent6, align: "right" });
}
function inShort(s, text) {
  txt(s, [{ text: "In short:  ", options: { bold: true, color: C.accent1 } }, { text }], { x: 0.6, y: 6.2, w: 12.13, h: 0.6, fontSize: 17, valign: "middle" });
}
function box(s, x, y, w, h, o = {}) {
  s.addShape(SH.RECTANGLE, { x, y, w, h, fill: { color: o.fill || C.background1 }, rectRadius: o.r === undefined ? 0.07 : o.r,
    line: { color: o.lineColor || LINE, width: o.lw || 0.75, dashType: o.dash || "solid" }, objectName: o.name || "Box" });
}
// a canvas cell: small caption on top, content below
function cell(s, x, y, w, h, title, body, o = {}) {
  box(s, x, y, w, h, o);
  const pad = 0.11;
  let ty = y + 0.07;
  if (title) { txt(s, title, { x: x + pad, y: ty, w: w - 2 * pad, h: 0.26, fontSize: o.tfs || 11, bold: true, color: o.tcol || C.accent1 }); ty += 0.29; }
  if (o.hint) { txt(s, o.hint, { x: x + pad, y: ty - 0.03, w: w - 2 * pad, h: 0.24, fontSize: 9.5, italic: true, color: C.accent6 }); ty += 0.25; }
  if (body) txt(s, body, { x: x + pad, y: title ? ty : y, w: w - 2 * pad, h: title ? y + h - ty - 0.05 : h, fontSize: o.fs || 12,
    color: o.col || C.text1, valign: title ? "top" : "middle", align: o.align || "left", bold: !!o.bold });
}
function num(s, x, y, n, d = 0.5, fill) { // plain bold number, no circle
  txt(s, String(n), { x, y, w: d, h: d, align: "center", valign: "middle", fontSize: d > 0.45 ? 22 : 14, bold: true, color: fill || C.accent1 });
}
function arrow(s, x, y, w = 0.35, h = 0.35, fill) { s.addShape(SH.RIGHT_ARROW, { x, y, w, h, fill: { color: fill || C.accent1 }, objectName: "Arrow" }); }
function pill(s, x, y, w, h, text, fill, col) {
  s.addShape(SH.RECTANGLE, { x, y, w, h, fill: { color: fill }, rectRadius: h / 2, objectName: "Pill" });
  txt(s, text, { x, y, w, h, fontSize: 11, bold: true, align: "center", valign: "middle", color: col || C.text1 });
}
function person(s, x, y, d) { // simple avatar: circle, head, shoulders
  s.addShape(SH.OVAL, { x, y, w: d, h: d, fill: { color: C.accent3 }, objectName: "Avatar" });
  s.addShape(SH.OVAL, { x: x + d * 0.34, y: y + d * 0.18, w: d * 0.32, h: d * 0.32, fill: { color: C.text2 }, objectName: "Avatar head" });
  s.addShape(SH.RECTANGLE, { x: x + d * 0.22, y: y + d * 0.56, w: d * 0.56, h: d * 0.28, fill: { color: C.text2 }, rectRadius: d * 0.12, objectName: "Avatar shoulders" });
}
function seg(s, x1, y1, x2, y2, color, width, o = {}) { // straight line between two points
  s.addShape(SH.LINE, { x: Math.min(x1, x2), y: Math.min(y1, y2), w: Math.abs(x2 - x1), h: Math.abs(y2 - y1), flipV: (y2 < y1) !== (x2 < x1),
    line: Object.assign({ color, width: width || 2 }, o), objectName: "Line" });
}

// mini sketch of each blank canvas, drawn in unit coordinates (0..1)
function G(cols, rows, x0, y0, w, h, c) {
  const out = [], gx = 0.03, gy = 0.07, cw = (w - (cols - 1) * gx) / cols, ch = (h - (rows - 1) * gy) / rows;
  for (let r = 0; r < rows; r++) for (let i = 0; i < cols; i++) out.push(["r", x0 + i * (cw + gx), y0 + r * (ch + gy), cw, ch, typeof c === "function" ? c(i, r) : c]);
  return out;
}
const DOT = (x, y, c) => ["o", x, y, 0.038, 0.13, c];
const THUMBS = {
  bmc: [...G(1, 1, 0, 0, 0.18, 0.68, "l"), ...G(1, 2, 0.21, 0, 0.18, 0.68, "l"), ["r", 0.42, 0, 0.16, 0.68, "y"], ...G(1, 2, 0.61, 0, 0.18, 0.68, "l"), ...G(1, 1, 0.82, 0, 0.18, 0.68, "l"), ...G(2, 1, 0, 0.76, 1, 0.24, "w")],
  persona: [["o", 0.04, 0.06, 0.2, 0.68, "l"], ["r", 0.06, 0.84, 0.16, 0.14, "y"], ...G(2, 2, 0.34, 0, 0.66, 1, "l")],
  journey: [...G(5, 1, 0, 0, 1, 0.22, "w"), DOT(0.08, 0.46, "y"), DOT(0.28, 0.32, "y"), DOT(0.48, 0.46, "y"), DOT(0.68, 0.36, "y"), DOT(0.88, 0.3, "y"), ...G(5, 1, 0, 0.72, 1, 0.28, "l")],
  grid: [...G(2, 2, 0.2, 0, 0.6, 1, (i, r) => (i === 1 && r === 0 ? "y" : "l")), DOT(0.3, 0.16, "o"), DOT(0.62, 0.2, "t"), DOT(0.66, 0.7, "o"), DOT(0.34, 0.68, "t")],
  usecase: [["o", 0.02, 0.22, 0.17, 0.58, "l"], ["r", 0.24, 0.44, 0.09, 0.12, "y"], ["r", 0.38, 0, 0.3, 1, "l"], ...[0, 1, 2, 3].map((i) => ["r", 0.41, 0.12 + i * 0.21, 0.24, 0.09, "t"]), ["r", 0.72, 0.44, 0.09, 0.12, "y"], ["r", 0.84, 0.15, 0.16, 0.7, "y"]],
  context: [...G(1, 3, 0, 0, 0.24, 1, "l"), ["r", 0.28, 0.44, 0.07, 0.12, "y"], ["r", 0.39, 0.05, 0.22, 0.9, "y"], ["r", 0.65, 0.44, 0.07, 0.12, "y"], ...G(1, 3, 0.76, 0, 0.24, 1, "l")],
  blueprint: [...G(4, 3, 0, 0, 1, 0.54, "w"), ["r", 0, 0.59, 1, 0.04, "o"], ...G(4, 2, 0, 0.68, 1, 0.32, "l")],
  capmap: G(6, 4, 0, 0, 1, 1, (i, r) => (r === 0 ? "w" : (i + r) % 4 === 0 ? "y" : "l")),
  capcard: [["r", 0, 0, 1, 0.22, "w"], ...G(3, 1, 0, 0.3, 1, 0.42, "l"), ["r", 0, 0.8, 1, 0.2, "o"]],
  asr: [...G(3, 1, 0, 0, 1, 1, "l"), ...[0, 1, 2].map((i) => ["r", 0.2 + i * 0.343, 0.1, 0.1, 0.13, "o"])],
  qatt: [...G(6, 1, 0, 0, 1, 0.4, (i) => (i === 5 ? "o" : "l")), ...G(3, 1, 0, 0.52, 1, 0.48, "w")],
  adr: [["r", 0, 0, 1, 0.2, "w"], ...G(4, 1, 0, 0.27, 1, 0.33, (i) => (i === 3 ? "y" : "l")), ...G(3, 1, 0, 0.67, 1, 0.33, "w")],
  okr: [["r", 0, 0, 1, 0.22, "y"], ...[0, 1, 2, 3].flatMap((i) => [["r", 0, 0.32 + i * 0.18, 0.4, 0.1, "l"], ["r", 0.45, 0.32 + i * 0.18, 0.55, 0.1, "w"], ["r", 0.45, 0.32 + i * 0.18, 0.55 * [0.2, 0.5, 0.35, 1][i], 0.1, "o"]])],
  roadmap: [...G(4, 1, 0.16, 0, 0.84, 0.2, "y"), ...[0, 1, 2].flatMap((r) => [["r", 0, 0.27 + r * 0.25, 0.13, 0.2, "o"], ...G(4, 1, 0.16, 0.27 + r * 0.25, 0.84, 0.2, r === 1 ? "l" : "w")])],
};
function thumb(s, kind, x, y, w, h) {
  const col = { l: C.accent3, y: C.accent2, o: C.accent4, w: C.background2, t: C.accent1 };
  THUMBS[kind].forEach(([sh, fx, fy, fw, fh, c]) => {
    if (sh === "o") s.addShape(SH.OVAL, { x: x + fx * w, y: y + fy * h, w: fw * w, h: fh * h, fill: { color: col[c] }, objectName: "Sketch" });
    else s.addShape(SH.RECTANGLE, { x: x + fx * w, y: y + fy * h, w: fw * w, h: fh * h, fill: { color: col[c] }, line: { color: LINE, width: 0.5 }, objectName: "Sketch" });
  });
}

// left panel "how to read it", one per canvas
const READ = {
  bmc: "Left: what it takes (partners, work, needs). Middle: the value. Right: who it is for and where they use it. Bottom: cost against payback.",
  persona: "Left: who the person is, in their own words. Right: their day, what they want, what stops them, and what makes them trust the tool.",
  journey: "Read left to right: one ticket's life. The lines show how the person feels. Orange = today, green = with AIForge.",
  grid: "Each group sits by power (up) and interest (right). The corner says how to treat them. Orange = a job with no owner yet.",
  usecase: "Left: who starts it and what must be true first. Middle: the 7 steps AIForge runs. Right: what comes out.",
  context: "Middle: AIForge inside our own machines (dashed line). Left: what it reads. Right: what it writes back. Bottom: what we assume, and known limits.",
  blueprint: "Read across: one example ticket, from ask to hand back. Above the orange line: what the person sees and does. Below: what AIForge does out of sight.",
  capmap: "Columns: the stages of getting a code change done. Each box: one thing the team must be able to do. Colour: who does it today.",
  capcard: "Zoom into ONE box of the capability map: \u201cBuild the change\u201d. Top: how good we are. Middle: what it needs. Bottom: what is missing.",
  asr: "Each pillar is one must-have rule. It shows how important it is, what breaks without it, and the proof it holds today.",
  qatt: "Read the top row as one sentence: who does what, where, to what, what should happen, and the number we measure.",
  adr: "Top: the problem. Middle: the options we looked at, one chosen. Bottom: the decision, what it means for us, and if we can undo it.",
  okr: "Dark bar: the goal. Each row: one number that shows progress, with why it matters. Compare today with the target.",
  roadmap: "Columns: quarters. Rows: product (what users get), platform (machines and models), people (who owns and uses it).",
};
// canvas slide frame: left = what the canvas is, right = the canvas itself filled for AIForge
const AX = 4.25, AY = 1.9, AW = 8.48, AH = 4.05;
function canvasSlide(o) {
  const s = content(o.section, o.name, [{ text: "It answers:  ", options: { bold: true, color: C.accent1 } }, { text: o.q }]);
  sticky(s, o.stage, `Canvas ${o.n} of ${TOTAL}`);
  const lab = (t, y) => txt(s, t, { x: 0.6, y: AY + y, w: 3.3, h: 0.26, fontSize: 11, bold: true, color: C.accent6, charSpacing: 1 });
  lab("WHAT IT IS", 0);
  txt(s, o.what, { x: 0.6, y: AY + 0.28, w: 3.3, h: 0.8, fontSize: 14 });
  lab("HOW TO READ IT", 1.12);
  txt(s, READ[o.thumb], { x: 0.6, y: AY + 1.4, w: 3.3, h: 1.3, fontSize: 12.5 });
  lab("IN AIFORGE", 2.82);
  txt(s, o.ex, { x: 0.6, y: AY + 3.1, w: 3.3, h: 0.95, fontSize: 13 });
  inShort(s, o.short);
  s.addNotes(o.notes);
  return s;
}

// =====================================================================
// PART 1 — why canvases
// =====================================================================
const S1 = "Why canvases help", S2 = "Why and who", S3 = "What the service is", S4 = "How it is designed", S5 = "Where it goes next", S6 = "Wrap-up";
pres.addSection({ title: S1 });

// ---------- 1. Title ----------
{
  const s = pres.addSlide({ masterName: "DARK", sectionTitle: S1 });
  txt(s, "IASA Masterclass  ·  Canvas guide", { x: 0.8, y: 0.7, w: 8, h: 0.4, fontSize: 16, color: C.accent6 });
  s.addText("IASA canvases, explained with AIForge", { placeholder: "title" });
  s.addText("What each canvas is for, and the same canvas filled in for our own AI developer.", { placeholder: "body" });
  [["First", "how canvases help"], ["Then", `${TOTAL} canvases, one by one`], ["Each time", "the AIForge example"]].forEach(([a, b], i) => {
    const x = 0.8 + i * 3.0;
    box(s, x, 5.0, 2.7, 0.95, { name: "Agenda box" });
    txt(s, [{ text: a, options: { fontSize: 12, color: C.accent6, breakLine: true } }, { text: b, options: { fontSize: 16, bold: true } }], { x: x + 0.15, y: 5.0, w: 2.4, h: 0.95, valign: "middle" });
  });
  txt(s, "Roles only. No names, no customer detail.", { x: 0.8, y: 6.6, w: 8, h: 0.35, fontSize: 12, color: C.accent6 });
  s.addNotes("This deck teaches the IASA canvases using one running example: AIForge, the tool that turns a ticket into a tested pull request on machines we own. First we look at why canvases help at all, then at each canvas in turn.");
}

// ---------- 2. How canvases help ----------
{
  const s = content(S1, "How canvases help", "Six reasons to fill a one-page canvas instead of writing a long document");
  sticky(s, "Start here", "Why bother?");
  const R = (x, y, w, h, fill, o = {}) => s.addShape(SH.RECTANGLE, { x, y, w, h, fill: { color: fill }, rectRadius: 0.03, line: { color: o.line || HEX.accent6, width: o.lw === undefined ? 0.75 : o.lw, dashType: o.dash || "solid" }, objectName: "Picture" });
  const pics = [
    (x, y) => { [0, 1, 2].forEach((i) => R(x + i * 0.07, y + 0.14 - i * 0.07, 0.42, 0.56, C.background2)); arrow(s, x + 0.66, y + 0.27, 0.22, 0.22, C.accent4); R(x + 0.96, y + 0.07, 0.42, 0.56, C.accent2, { line: HEX.accent4, lw: 1.25 }); },
    (x, y) => { [0, 1, 2, 3].forEach((i) => R(x, y + 0.08 + i * 0.16, i === 3 ? 0.3 : 0.5, 0.07, C.accent6, { lw: 0 })); arrow(s, x + 0.6, y + 0.27, 0.22, 0.22, C.accent4); R(x + 0.9, y + 0.05, 0.48, 0.62, C.background1, { line: HEX.accent1, lw: 1.25 }); R(x + 0.96, y + 0.11, 0.16, 0.5, C.accent3, { lw: 0 }); R(x + 1.16, y + 0.11, 0.16, 0.22, C.accent2, { lw: 0 }); R(x + 1.16, y + 0.39, 0.16, 0.22, C.accent3, { lw: 0 }); },
    (x, y) => { R(x, y, 1.38, 0.72, C.background2); [[0.1, 0.1, C.accent2], [0.42, 0.16, C.accent3], [0.78, 0.08, C.accent2], [0.24, 0.42, C.accent3], [0.6, 0.44, C.accent2], [1.0, 0.4, C.accent4]].forEach(([dx, dy, c]) => R(x + dx, y + dy, 0.24, 0.22, c, { lw: 0 })); },
    (x, y) => { [0, 1, 2].forEach((i) => { R(x + i * 0.52, y + 0.2, 0.34, 0.34, i === 2 ? C.accent2 : C.accent3, { line: HEX.accent1 }); if (i < 2) arrow(s, x + i * 0.52 + 0.36, y + 0.29, 0.14, 0.16, C.accent4); }); },
    (x, y) => { seg(s, x + 0.15, y + 0.36, x + 1.23, y + 0.36, HEX.accent6, 2); [C.accent1, C.accent4, C.accent5].forEach((c, i) => s.addShape(SH.OVAL, { x: x + i * 0.54, y: y + 0.21, w: 0.3, h: 0.3, fill: { color: c }, objectName: "Picture" })); },
    (x, y) => { for (let r = 0; r < 2; r++) for (let i = 0; i < 3; i++) { const gap = r === 1 && i === 1; R(x + i * 0.47, y + 0.04 + r * 0.35, 0.42, 0.3, gap ? C.background1 : C.accent3, gap ? { line: HEX.accent4, lw: 1.5, dash: "dash" } : { lw: 0 }); } },
  ];
  const items = [
    ["One page, not a book", "One page gets read. Fifty pages do not."],
    ["A picture beats words", "A box you must fill forces a clear answer."],
    ["Everyone sees one wall", "Pin it up. Fill it together with sticky notes."],
    ["Each canvas feeds the next", "The person shapes the journey; the journey shapes the rules."],
    ["Choices can be traced", "Rule, choice, number — linked. No arguing again later."],
    ["Gaps show up early", "An empty box is a question nobody has answered."],
  ];
  items.forEach(([h, b], i) => {
    const col = i % 3, row = Math.floor(i / 3);
    const x = 0.6 + col * 4.13, y = 1.95 + row * 2.03;
    box(s, x, y, 3.83, 1.83, { name: "Reason card" });
    num(s, x + 0.25, y + 0.22, i + 1, 0.5, row === 0 ? C.accent1 : C.accent4);
    txt(s, h, { x: x + 0.9, y: y + 0.22, w: 2.8, h: 0.5, fontSize: 17, bold: true, color: C.text2, valign: "middle" });
    txt(s, b, { x: x + 0.25, y: y + 0.88, w: 1.85, h: 0.85, fontSize: 13 });
    pics[i](x + 2.25, y + 0.92);
  });
  inShort(s, "a canvas is a one-page question sheet. Fill the boxes and anyone can check the thinking.");
  s.addNotes("These six points come from the IASA toolkit lesson: least documentation, visual thinking, working together on a wall, connected ideas, traceable decisions, and finding problems early.");
}

// ---------- 3. The canvases at a glance ----------
const STAGES = [
  ["Why?", "the business", [["Business Model Canvas", "How it gives value, to whom, at what cost"]]],
  ["Who?", "the people", [["Persona Card", "One kind of user: their day, wants, blocks"], ["Customer Journey Map", "Each step the user takes, and how it feels"], ["Power / Interest Grid", "Who has a say, who cares, who must own it"]]],
  ["What?", "the service", [["Use Case Card", "One job: who starts it, the steps, the result"], ["Context View", "What is inside, and what it talks to"], ["Service Blueprint", "What the user sees, and what runs behind"], ["Capability Map", "Everything the business must be good at"], ["Capability Card", "One ability: people, process, tools"]]],
  ["How?", "the design", [["ASR Card", "The few must-have rules that shape the design"], ["QATT Card", "A quality goal written as a number to test"], ["Decision Record (ADR)", "What we chose, what else we looked at, why"]]],
  ["Where next?", "the plan", [["OKR Card", "The goal, and the numbers that prove it"], ["Roadmap Canvas", "What happens when: product, platform, people"]]],
];
{
  const s = content(S1, "The canvases at a glance", `${TOTAL} canvases, grouped by the question each one answers`);
  sticky(s, "The map", "Five questions");
  let n = 0;
  const w = 2.3, gap = 0.1575;
  STAGES.forEach(([q, cap, list], i) => {
    const x = 0.6 + i * (w + gap);
    s.addShape(SH.PENTAGON, { x, y: 1.8, w, h: 0.7, fill: { color: i % 2 ? C.accent1 : C.text2 }, objectName: "Stage" });
    txt(s, [{ text: q, options: { fontSize: 18, bold: true, breakLine: true } }, { text: cap, options: { fontSize: 11 } }],
      { x: x + 0.15, y: 1.8, w: w - 0.55, h: 0.7, color: C.background1, valign: "middle" });
    list.forEach(([name, hint], j) => {
      n += 1;
      const y = 2.62 + j * 0.71;
      box(s, x, y, w, 0.65, { name: "Canvas chip" });
      num(s, x + 0.04, y + 0.05, n, 0.3);
      txt(s, [{ text: name, options: { fontSize: 11.5, bold: true, color: C.text2, breakLine: true } }, { text: hint, options: { fontSize: 10, color: C.text1 } }],
        { x: x + 0.38, y: y + 0.05, w: w - 0.45, h: 0.57, valign: "top" });
    });
  });
  inShort(s, "start with why and who. The design canvases only make sense after those.");
  s.addNotes("The numbers on the chips are the order we walk through them. Every canvas slide has the same shape: on the left what the canvas is and how it helps, on the right the canvas itself filled in for AIForge.");
}

// ---------- 4. Our example ----------
{
  const s = content(S1, "Our example: AIForge", "One input, one output — and nobody has to watch in between");
  sticky(s, "Running example", "AIForge");
  const boxes = [
    ["A ticket", "Written in plain words, the way you would ask a colleague", C.background1, C.text2],
    ["AIForge", "A small team of AI agents on our own machines plans, writes, tests and checks the change", C.accent1, C.background1],
    ["A pull request", "A tested code change, ready for a person to read and accept", C.background1, C.text2],
  ];
  boxes.forEach(([h, b, fill, col], i) => {
    const x = 0.6 + i * 4.2;
    s.addShape(SH.RECTANGLE, { x, y: 1.95, w: 3.6, h: 2.1, fill: { color: fill }, rectRadius: 0.1, line: { color: HEX.accent3, width: 1 }, objectName: "Flow box" });
    txt(s, h, { x: x + 0.3, y: 2.15, w: 3.0, h: 0.6, fontSize: 26, bold: true, color: col });
    txt(s, b, { x: x + 0.3, y: 2.8, w: 3.0, h: 1.2, fontSize: 16, color: col });
    if (i < 2) arrow(s, x + 3.68, 2.78, 0.45, 0.45);
  });
  const facts = [["Our machines only", "No cloud. No code or data leaves the building."], ["Seven small agents", "Each has one small job and only the context it needs."], ["A person acts twice", "Write the ticket. Read the pull request."]];
  facts.forEach(([h, b], i) => {
    const x = 0.6 + i * 4.2;
    box(s, x, 4.35, 3.6, 1.55, { fill: C.accent2, lineColor: LINE, name: "Fact card" });
    txt(s, h, { x: x + 0.3, y: 4.5, w: 3.0, h: 0.45, fontSize: 18, bold: true, color: C.text2 });
    txt(s, b, { x: x + 0.3, y: 4.97, w: 3.0, h: 0.85, fontSize: 14 });
  });
  inShort(s, "keep this picture in mind — every canvas that follows describes it from a different side.");
  s.addNotes("AIForge works in a defence setting where cloud AI is not allowed, so it runs on hardware we own. That one fact shows up on almost every canvas.");
}

// ---------- 5. How AIForge works inside ----------
{
  const s = content(S1, "How AIForge works inside", "Seven small AI agents, each with one small job, in order");
  sticky(s, "Running example", "The agent line");
  const roles = [["Enhancer", "makes the ticket clear"], ["Architect", "splits the work, writes one plan"], ["Senior dev", "sets the shape of the code"], ["Developer", "writes each part"], ["Tester", "writes and runs tests"], ["Reviewer", "a second AI checks"], ["Joiner", "joins it all, builds until it passes"]];
  const w = 1.55, gap = (12.13 - 7 * w) / 6;
  roles.forEach(([r, d], i) => {
    const x = 0.6 + i * (w + gap);
    box(s, x, 1.95, w, 1.75, { name: "Agent" });
    num(s, x + w / 2 - 0.22, 2.05, i + 1, 0.44, i === 5 ? C.accent4 : C.accent1);
    txt(s, r, { x: x + 0.08, y: 2.55, w: w - 0.16, h: 0.35, fontSize: 15, bold: true, color: C.text2, align: "center" });
    txt(s, d, { x: x + 0.1, y: 2.92, w: w - 0.2, h: 0.72, fontSize: 12.5, align: "center" });
    if (i < 6) arrow(s, x + w + gap / 2 - 0.09, 2.72, 0.18, 0.22, C.accent4);
  });
  // why split: one big job does not fit, small jobs do
  box(s, 0.6, 3.9, 12.13, 2.05, { fill: C.accent2, lineColor: LINE, name: "Why split" });
  txt(s, "Why split the work?", { x: 0.85, y: 4.02, w: 3.4, h: 0.4, fontSize: 18, bold: true, color: C.text2 });
  txt(s, "A local AI model can hold only 3–5 files in mind at once (the dashed box). One big job does not fit. Small jobs do.", { x: 0.85, y: 4.45, w: 3.4, h: 1.4, fontSize: 14 });
  const frame = (x, label) => {
    s.addShape(SH.RECTANGLE, { x, y: 4.4, w: 1.5, h: 0.8, fill: { color: C.background1, transparency: 100 }, rectRadius: 0.05, line: { color: HEX.dk2, width: 2, dashType: "dash" }, objectName: "What the model can hold" });
    txt(s, label, { x: x - 0.6, y: 5.5, w: 2.7, h: 0.3, fontSize: 12.5, bold: true, color: C.text2, align: "center" });
  };
  s.addShape(SH.RECTANGLE, { x: 4.95, y: 4.1, w: 2.5, h: 1.3, fill: { color: C.accent4 }, rectRadius: 0.06, objectName: "Big job" });
  txt(s, "12 files", { x: 4.95, y: 4.1, w: 2.5, h: 1.3, fontSize: 16, bold: true, color: C.background1, align: "center", valign: "middle" });
  frame(5.45, "One big job: does not fit");
  s.addShape(SH.RECTANGLE, { x: 9.3, y: 4.25, w: 2.1, h: 1.1, fill: { color: C.background1 }, rectRadius: 0.06, objectName: "Room to spare" });
  s.addShape(SH.RECTANGLE, { x: 9.8, y: 4.55, w: 0.8, h: 0.5, fill: { color: C.accent5 }, rectRadius: 0.05, objectName: "Small job" });
  txt(s, "3 files", { x: 9.8, y: 4.55, w: 0.8, h: 0.5, fontSize: 12, bold: true, color: C.background1, align: "center", valign: "middle" });
  frame(9.6, "One small job: fits");
  arrow(s, 8.05, 4.75, 0.6, 0.45, C.text2);
  inShort(s, "one shared plan first, tests before code, and nothing is accepted unless it builds.");
  s.addNotes("Simple tickets skip most of this line; only real multi-file work runs all seven steps. The yellow panel is the key idea: same models, same machines — only the way the work was cut up changed.");
}

// =====================================================================
// PART 2 — canvases
// =====================================================================
pres.addSection({ title: S2 });

// ---------- 5. Business Model Canvas ----------
{
  const s = canvasSlide({ section: S2, n: 1, stage: "Why?", name: "Business Model Canvas", q: "how does this create value, and for whom?",
    thumb: "bmc", what: "Nine boxes that show how something gives value, to whom, and at what cost.",
    ex: "Ticket in, tested pull request out. It costs machines and one person; it gives senior hours back.",
    short: "AIForge sells nothing. It gives senior hours back, inside our own walls.",
    notes: "This is the internal-product view of the business model: the 'customers' are our own senior developers, junior developers and QA engineers (who use it for test automation), and the 'revenue' is time handed back. No customer or programme detail is shown, on purpose." });
  const cw = AW / 5, g = 0.07, top = 2.72, hh = (top - g) / 2;
  const B = (i, y, h, t, b, o) => cell(s, AX + i * cw, y, cw - g, h, t, b, o);
  B(0, AY, top, "WHO HELPS", lines(["IT operations", "Platform operator"]), { hint: "partners it relies on" });
  B(1, AY, hh, "WHAT IT DOES", "Plan, write, test, check", { hint: "its main work" });
  B(1, AY + hh + g, hh, "WHAT IT NEEDS", lines(["Own machines", "AI models", "Memory notes"]), { hint: "cannot run without" });
  B(2, AY, top, "WHAT IT GIVES", lines(["Ticket in, tested pull request out.", "", "Code never leaves the building."]), { hint: "the value, in short", fill: C.accent2, lineColor: HEX.accent4, lw: 1.5, fs: 13, bold: true, tcol: C.text2 });
  B(3, AY, hh, "TRUST", "Every pull request says if it really worked", { hint: "why they come back" });
  B(3, AY + hh + g, hh, "HOW TO REACH IT", lines(["Chat", "Ticket tracker"]), { hint: "where people use it" });
  B(4, AY, top, "WHO IT SERVES", lines(["Senior developers", "Junior developers", "QA engineers (test automation)"]), { hint: "the users" });
  const by = AY + top + g, bh = AH - top - g, half = AW / 2;
  cell(s, AX, by, half - g, bh, "WHAT IT COSTS", "Machines, computing time, and one person to run it", { hint: "what we spend to run it", fill: TINT.orange, tcol: C.accent4 });
  cell(s, AX + half, by, half - g, bh, "WHAT COMES BACK", "Senior hours freed for hard work; juniors move faster; QA gets tests written for them", { hint: "the payback: time, not money", fill: TINT.green, tcol: C.accent5 });
}

// ---------- 6. Persona Card ----------
{
  const s = canvasSlide({ section: S2, n: 2, stage: "Who?", name: "Persona Card", q: "who exactly are we building for?",
    thumb: "persona", what: "One page about one real kind of user, in their own words.",
    ex: "The senior developer: “Half my week goes on work I already know how to do.”",
    short: "built for senior developers first, then juniors and QA engineers.",
    notes: "Three personas exist: senior developer (primary), junior developer, QA engineer (uses AIForge to write and run automated tests). Only the primary one is drawn in full. Honest adoption test: does a junior or QA engineer file a ticket, or still walk over to a senior? Today, mostly the second." });
  box(s, AX, AY, AW, AH, { name: "Persona card" });
  person(s, AX + 0.6, AY + 0.2, 1.2);
  pill(s, AX + 0.45, AY + 1.5, 1.6, 0.32, "PRIMARY PERSONA", C.accent1, C.background1);
  txt(s, "Senior developer", { x: AX + 0.1, y: AY + 1.88, w: 2.3, h: 0.35, fontSize: 15, bold: true, color: C.text2, align: "center" });
  txt(s, "“Half my week goes on work I already know how to do.”", { x: AX + 0.2, y: AY + 2.25, w: 2.1, h: 0.85, fontSize: 13, italic: true, color: C.accent1, align: "center" });
  txt(s, [{ text: "ALSO FOR", options: { fontSize: 10, bold: true, color: C.accent6, breakLine: true } },
    { text: "Junior developers", options: { bold: true, breakLine: true } }, { text: "help without waiting for a senior", options: { breakLine: true } },
    { text: "QA engineers", options: { bold: true, breakLine: true } }, { text: "test automation written for them" }],
    { x: AX + 0.05, y: AY + 3.0, w: 2.45, h: 0.98, fontSize: 10, align: "center" });
  const qx = AX + 2.55, qw = (AW - 2.55 - 0.2 - 0.1) / 2, qh = (AH - 0.4 - 0.1) / 2;
  const Q = [
    ["THEIR DAY", ["Owns the hard parts of a live system", "Juniors and QA ask them for help all day", "Little quiet time for deep work"], C.background2, C.accent1],
    ["WHAT THEY WANT", ["Routine code done for them", "Keep the hard, interesting work", "Never hand code to an outside service"], TINT.green, C.accent5],
    ["WHAT BLOCKS THEM", ["A pull request they do not trust", "A tool that stops half-way and says nothing", "Lots of setup before the tool helps"], TINT.orange, C.accent4],
    ["WHAT EARNS TRUST", ["It compiles, or it says it failed", "“I could not do this” in the first line", "A second AI checked the work"], TINT.teal, C.accent1],
  ];
  Q.forEach(([t, items, fill, tcol], i) => {
    cell(s, qx + (i % 2) * (qw + 0.1), AY + 0.2 + Math.floor(i / 2) * (qh + 0.1), qw, qh, t,
      items.map((v, j) => ({ text: v, options: { bullet: { indent: 12 }, breakLine: j < items.length - 1 } })), { fill, tcol, fs: 12.5 });
  });
}

// ---------- 7. Customer Journey Map ----------
{
  const s = canvasSlide({ section: S2, n: 3, stage: "Who?", name: "Customer Journey Map", q: "where does the person wait, and how does it feel?",
    thumb: "journey", what: "The steps a person goes through, and how each step feels.",
    ex: "Today a ticket waits days for a senior. With AIForge the work starts at once.",
    short: "the cost was never the typing — it was the waiting. AIForge removes the wait.",
    notes: "Read the orange line first (today), then the green one (with AIForge). The person now joins at the pull request, not before it." });
  const lw = 1.3, cw = (AW - lw) / 5, x0 = AX + lw;
  const steps = ["Ticket raised", "Picked up", "Code written", "Tested, checked", "Accepted"];
  const today = ["sits in the backlog", "waits for a senior to be free", "done between other work", "rushed at the end", "days after it was raised"];
  const after = ["picked up as written", "a run starts, nobody waits", "agents write it in a copy of the code", "tests first, then a second AI checks", "pull request ready to read"];
  steps.forEach((st, i) => {
    s.addShape(SH.CHEVRON, { x: x0 + i * cw, y: AY, w: cw - 0.03, h: 0.5, fill: { color: C.text2 }, objectName: "Step" });
    txt(s, st, { x: x0 + i * cw + 0.22, y: AY, w: cw - 0.47, h: 0.5, fontSize: 11, bold: true, color: C.background1, align: "center", valign: "middle" });
  });
  // feeling curve
  const fy = AY + 0.6, fh = 1.15;
  box(s, x0, fy, AW - lw - 0.03, fh, { name: "Feeling band" });
  txt(s, [{ text: "How it feels", options: { bold: true, breakLine: true } }, { text: "good at the top", options: { fontSize: 10, color: C.accent6, breakLine: true } }, { text: "orange = today", options: { fontSize: 10, color: C.accent4, breakLine: true } }, { text: "green = AIForge", options: { fontSize: 10, color: C.accent5 } }], { x: AX, y: fy, w: lw - 0.1, h: fh, fontSize: 13, color: C.text2, valign: "middle" });
  const moodY = (m) => fy + fh - 0.2 - (m - 1) * 0.19;
  const curve = (moods, color) => {
    const pts = moods.map((m, i) => [x0 + i * cw + cw / 2, moodY(m)]);
    pts.forEach((p, i) => { if (i) seg(s, pts[i - 1][0], pts[i - 1][1], p[0], p[1], color, 2.5); });
    pts.forEach((p) => s.addShape(SH.OVAL, { x: p[0] - 0.1, y: p[1] - 0.1, w: 0.2, h: 0.2, fill: { color }, line: { color: "FFFFFF", width: 1.5 }, objectName: "Feeling point" }));
  };
  curve([2, 1, 2, 1, 2], HEX.accent4);
  curve([4, 5, 4, 4, 5], HEX.accent5);
  const rows = [["Today", today, TINT.orange, C.accent4], ["With AIForge", after, TINT.green, C.accent5]];
  rows.forEach(([label, vals, fill, col], r) => {
    const y = fy + fh + 0.1 + r * 1.1;
    s.addShape(SH.RECTANGLE, { x: AX, y, w: lw - 0.1, h: 1.0, fill: { color: col }, rectRadius: 0.08, objectName: "Row label" });
    txt(s, label, { x: AX + 0.05, y, w: lw - 0.2, h: 1.0, fontSize: 14, bold: true, color: C.background1, align: "center", valign: "middle" });
    vals.forEach((v, i) => cell(s, x0 + i * cw, y, cw - 0.07, 1.0, null, v, { fill, lineColor: fill, align: "center", fs: 12 }));
  });
}

// ---------- 8. Power / Interest Grid ----------
{
  const s = canvasSlide({ section: S2, n: 4, stage: "Who?", name: "Power / Interest Grid", q: "who must we win over, and who must own it?",
    thumb: "grid", what: "Up = power: can they stop or approve it? Right = interest: how much does it touch their work?",
    ex: "Developers and QA use it. Three jobs (orange) still have no owner.",
    short: "the tool works. What is left is people — three jobs still have no owner.",
    notes: "Read it corner by corner. Top right (manage closely) = people who decide and care: meet them often. Top left (keep satisfied) = people who can stop it but are not involved yet. Bottom right (keep informed) = the users: tell them every change. Bottom left (monitor) = not involved yet. Orange boxes are the three jobs with no owner today: IT operations must own the AI models, QA must own the test check on AI pull requests, and the platform needs a second operator." });
  const gx = AX + 0.4, gy = AY, gw = AW - 0.4, gh = 3.66, qw = gw / 2, qh = gh / 2;
  const quads = [
    ["Keep satisfied", "high power · low interest", "Can stop it, but not involved yet. Keep them happy.", 0, 0, C.background1, [
      ["IT operations", "Run our machines. Next: own the AI models.", true]]],
    ["Manage closely", "high power · high interest", "Decide and care. Meet them often.", 1, 0, TINT.teal, [
      ["Engineering lead", "Decides if teams use AIForge.", false],
      ["Platform operator", "The one person who runs it. Next: a second person.", true]]],
    ["Monitor", "low power · low interest", "Not involved yet. Check in now and then.", 0, 1, C.background1, [
      ["Junior developers", "Few use it yet. Goal: start using it in Q3.", false]]],
    ["Keep informed", "low power · high interest", "The daily users. Tell them every change.", 1, 1, C.background1, [
      ["Senior developers", "Main users. Hand it their routine tickets.", false],
      ["QA engineers", "Use it for test automation. Next: own the test check.", true]]],
  ];
  quads.forEach(([title, tag, meaning, cx, cy, fill, people]) => {
    const x = gx + cx * qw, y = gy + cy * qh;
    s.addShape(SH.RECTANGLE, { x, y, w: qw, h: qh, fill: { color: fill }, line: { color: LINE, width: 1 }, objectName: "Quadrant" });
    txt(s, [{ text: title, options: { bold: true, color: C.text2, fontSize: 13 } }, { text: "   " + tag, options: { color: C.accent6, fontSize: 10 } }],
      { x: x + 0.1, y: y + 0.06, w: qw - 0.2, h: 0.28, valign: "middle" });
    txt(s, meaning, { x: x + 0.1, y: y + 0.34, w: qw - 0.2, h: 0.24, fontSize: 10.5, italic: true, color: C.accent6 });
    people.forEach(([who, why, open], j) => {
      const by = y + 0.64 + j * 0.57;
      box(s, x + 0.12, by, qw - 0.24, 0.5, { fill: C.background1, lineColor: open ? HEX.accent4 : LINE, lw: open ? 1.5 : 0.75, name: "Group" });
      txt(s, [{ text: who, options: { bold: true, color: open ? C.accent4 : C.accent1, breakLine: true } }, { text: why }],
        { x: x + 0.22, y: by + 0.03, w: qw - 0.44, h: 0.44, fontSize: 10.5, valign: "middle" });
    });
  });
  txt(s, "POWER  →", { x: AX - 1.62, y: gy + gh / 2 - 0.15, w: 3.6, h: 0.3, fontSize: 11, bold: true, color: C.text2, align: "center", valign: "middle", rotate: 270, charSpacing: 1.5 });
  txt(s, "INTEREST  →", { x: gx, y: gy + gh + 0.07, w: qw * 1.2, h: 0.3, fontSize: 11, bold: true, color: C.text2, align: "left", charSpacing: 1.5 });
  box(s, gx + gw - 3.55, gy + gh + 0.1, 0.3, 0.22, { lineColor: HEX.accent4, lw: 1.5, name: "Legend" });
  txt(s, "orange = a job with no owner yet", { x: gx + gw - 3.15, y: gy + gh + 0.07, w: 3.15, h: 0.3, fontSize: 11, color: C.accent4, valign: "middle" });
}

pres.addSection({ title: S3 });

// ---------- 9. Use Case Card ----------
{
  const s = canvasSlide({ section: S3, n: 5, stage: "What?", name: "Use Case Card", q: "who starts it, what happens, and what comes out?",
    thumb: "usecase", what: "One job the system does: who starts it, the steps, the result.",
    ex: "A developer or QA engineer files a ticket. Seven steps later a pull request is ready to read.",
    short: "the senior spends minutes reading instead of hours writing.",
    notes: "The use case is 'one small change'. Simple tickets skip most of the seven steps; only real multi-file work runs them all." });
  const c1 = 2.45, c2 = 3.55, c3 = AW - c1 - c2 - 0.7;
  box(s, AX, AY, c1, 1.95, { name: "Actor card" });
  person(s, AX + 0.15, AY + 0.4, 0.75);
  txt(s, "ACTOR AND TRIGGER", { x: AX + 0.11, y: AY + 0.07, w: c1 - 0.2, h: 0.26, fontSize: 11, bold: true, color: C.accent1 });
  txt(s, [{ text: "Developer or QA engineer", options: { bold: true, breakLine: true } }, { text: "files a ticket in the tracker" }], { x: AX + 1.0, y: AY + 0.4, w: c1 - 1.1, h: 0.8, fontSize: 12.5, valign: "middle" });
  pill(s, AX + 0.15, AY + 1.4, c1 - 0.3, 0.36, "Used a few times a week", C.accent3, C.text2);
  cell(s, AX, AY + 2.05, c1, AH - 2.05, "BEFORE IT STARTS", [
    { text: "The ticket names a real project", options: { bullet: { indent: 12 }, breakLine: true } },
    { text: "The AI models are ready", options: { bullet: { indent: 12 }, breakLine: true } },
    { text: "The code builds before we start", options: { bullet: { indent: 12 } } }], { fs: 12, hint: "must be true, or the run stops" });
  arrow(s, AX + c1 + 0.03, AY + AH / 2 - 0.15, 0.3, 0.3);
  const fx = AX + c1 + 0.35;
  box(s, fx, AY, c2, AH, { name: "Main flow" });
  txt(s, "MAIN FLOW", { x: fx + 0.11, y: AY + 0.07, w: c2 - 0.2, h: 0.26, fontSize: 11, bold: true, color: C.accent1 });
  const flow = ["Someone files a ticket in plain words", "The ticket is rewritten so it is clear", "The work is split; one shared plan is written", "Each part is built in its own copy of the code", "Tests are written, then run against the build", "A second AI checks the change", "A pull request opens with an honest result"];
  flow.forEach((t, i) => {
    const y = AY + 0.4 + i * 0.515;
    num(s, fx + 0.12, y + 0.07, i + 1, 0.34, i === 6 ? C.accent4 : C.accent1);
    txt(s, t, { x: fx + 0.56, y, w: c2 - 0.66, h: 0.48, fontSize: 12.5, valign: "middle" });
  });
  arrow(s, fx + c2 + 0.03, AY + AH / 2 - 0.15, 0.3, 0.3);
  const ox = fx + c2 + 0.35;
  box(s, ox, AY, c3, AH, { fill: TINT.green, lineColor: HEX.accent5, name: "Outcome" });
  txt(s, "OUTCOME", { x: ox + 0.11, y: AY + 0.07, w: c3 - 0.2, h: 0.26, fontSize: 11, bold: true, color: C.accent5 });
  const outs = [["If it worked", "a pull request for a person to read and accept"], ["If it could not", "it says so in the first line — no fake success"], ["Either way", "a record of what each step did"]];
  outs.forEach(([a, b], i) => txt(s, [{ text: a, options: { bold: true, breakLine: true } }, { text: b }], { x: ox + 0.11, y: AY + 0.5 + i * 1.15, w: c3 - 0.2, h: 1.0, fontSize: 12.5 }));
}

// ---------- 10. Context View ----------
{
  const s = canvasSlide({ section: S3, n: 6, stage: "What?", name: "Context View", q: "what is inside the system, and what does it touch?",
    thumb: "context", what: "The system drawn as one box: what it reads, what it writes back, and where its edge is.",
    ex: "AIForge reads a ticket, our code and its memory notes. It writes back a pull request, a run record and new notes. All on our own machines.",
    short: "write the unknowns down, not just the boxes — the edges are where runs fail.",
    notes: "Walk it left to right with the example ticket 'Add a CSV export to the orders report'. The ticket comes from the tracker; AIForge reads the git repo it must change and the OKF memory notes from past runs (what worked, what failed in this repo). Out comes a pull request on our git server, a record of every agent step, and new notes for next time. The dashed line is the edge of our own machines: nothing crosses it." });
  const iw = 2.45, cwid = 2.3, cx = AX + iw + 0.6, ox = cx + cwid + 0.6, th = 2.3;
  txt(s, "WHAT IT READS", { x: AX, y: AY, w: iw, h: 0.26, fontSize: 11, bold: true, color: C.accent1 });
  txt(s, "WHAT IT WRITES BACK", { x: ox, y: AY, w: iw, h: 0.26, fontSize: 11, bold: true, color: C.accent5 });
  const ins = [["A ticket", "e.g. “Add CSV export to the orders report”"], ["Our code", "the git repo the change goes into"], ["Memory notes", "OKF notes: what worked before"]];
  const outs = [["A pull request", "on our git server, for a person to review"], ["A run record", "every agent step, kept to read later"], ["New memory notes", "lessons saved as OKF notes"]];
  const io = (list, x, fill, line) => list.forEach(([h, d], i) => {
    box(s, x, AY + 0.32 + i * 0.67, iw, 0.6, { fill, lineColor: line });
    txt(s, [{ text: h, options: { bold: true, breakLine: true } }, { text: d, options: { fontSize: 10.5, color: C.text2 } }], { x: x + 0.1, y: AY + 0.32 + i * 0.67, w: iw - 0.2, h: 0.6, fontSize: 12, valign: "middle" });
  });
  io(ins, AX, TINT.teal, LINE); io(outs, ox, TINT.green, HEX.accent5);
  arrow(s, AX + iw + 0.1, AY + 1.0, 0.4, 0.4);
  arrow(s, cx + cwid + 0.1, AY + 1.0, 0.4, 0.4, C.accent5);
  box(s, cx - 0.08, AY, cwid + 0.16, th, { fill: C.background2, lineColor: HEX.accent4, lw: 1.75, dash: "dash", r: 0.12, name: "System boundary" });
  s.addShape(SH.RECTANGLE, { x: cx + 0.06, y: AY + 0.38, w: cwid - 0.12, h: th - 0.54, fill: { color: C.text2 }, rectRadius: 0.1, objectName: "AIForge" });
  txt(s, "dashed line = our own machines", { x: cx - 0.1, y: AY + 0.07, w: cwid + 0.2, h: 0.26, fontSize: 10, italic: true, color: C.accent4, align: "center" });
  txt(s, [{ text: "AIForge", options: { fontSize: 19, bold: true, color: C.accent2, breakLine: true } }, { text: "7 small AI agents", options: { breakLine: true } }, { text: "plan, write, test,", options: { breakLine: true } }, { text: "check, join" }],
    { x: cx + 0.15, y: AY + 0.42, w: cwid - 0.3, h: th - 0.62, fontSize: 12.5, color: C.background1, align: "center", valign: "middle" });
  const by = AY + th + 0.15, bh = AH - th - 0.15, bw = (AW - 0.12) / 2;
  const bl = (a) => a.map((v, j) => ({ text: v, options: { bullet: { indent: 12 }, breakLine: j < a.length - 1 } }));
  cell(s, AX, by, bw, bh, "WHAT WE ASSUME", bl(["The AI models are running on our machines", "They stay up for the whole run", "The ticket names a real project"]), { fs: 12, hint: "if any is false, the run fails" });
  cell(s, AX + bw + 0.12, by, bw, bh, "WHAT TO BEWARE OF", bl(["About 3–5 files per ticket is today's limit", "Some languages are too hard for small models", "Shared machines: few tickets at once"]), { fs: 12, hint: "known limits today", fill: TINT.orange, tcol: C.accent4 });
}

// ---------- 11. Service Blueprint ----------
{
  const s = canvasSlide({ section: S3, n: 7, stage: "What?", name: "Service Blueprint", q: "what does the person see, and what runs behind it?",
    thumb: "blueprint", what: "One service shown in layers: what the person meets on top, the work behind it below.",
    ex: "A QA engineer files “Add CSV export to the orders report”. They only write the ticket and read the pull request. The agents do the rest.",
    short: "the person acts twice: file the ticket, read the result. The rest is below the line.",
    notes: "Follow the example ticket across the four stages. Top three rows are what the person sees and does, and what AIForge shows them. Below the orange line is everything they never see: which agent does what, and what the platform provides. The design work is all below the line; the person's experience is just two moments." });
  const lw = 1.55, cw = (AW - lw) / 4, x0 = AX + lw, rh = 0.6, pitch = 0.65;
  ["1. Ask", "2. Work", "3. Check", "4. Hand back"].forEach((c, i) => {
    s.addShape(SH.RECTANGLE, { x: x0 + i * cw, y: AY, w: cw - 0.07, h: 0.4, fill: { color: C.text2 }, rectRadius: 0.06, objectName: "Stage" });
    txt(s, c, { x: x0 + i * cw, y: AY, w: cw - 0.07, h: 0.4, fontSize: 13, bold: true, color: C.background1, align: "center", valign: "middle" });
  });
  const rows = [
    ["The person sees", ["their ticket in the tracker", "progress: step 3 of 7", "test results", "a pull request + a short summary"], C.background1, C.accent1],
    ["The person does", ["writes it in plain words", "nothing — back to own work", "nothing", "reads, comments, accepts"], C.background1, C.accent1],
    ["AIForge shows", ["“picked up” on the ticket", "a work copy of the code", "build and tests running", "the pull request opens"], TINT.teal, C.accent1],
    ["AI agents (unseen)", ["Enhancer makes the ticket clear", "Architect plans; Developers write", "Tester, Reviewer, Joiner check", "summary of what changed"], C.accent3, C.text2],
    ["Platform (unseen)", ["ticket store", "AI models on our machines", "build tools, test runners", "run record + memory notes saved"], C.accent3, C.text2],
  ];
  rows.forEach(([label, vals, fill, col], r) => {
    const y = AY + 0.47 + r * pitch + (r > 2 ? 0.3 : 0);
    txt(s, label, { x: AX, y, w: lw - 0.1, h: rh, fontSize: 12.5, bold: true, color: col, valign: "middle" });
    vals.forEach((v, i) => cell(s, x0 + i * cw, y, cw - 0.07, rh, null, v, { fill, align: "center", fs: 11.5 }));
  });
  const ly = AY + 0.47 + 3 * pitch - 0.01;
  seg(s, AX, ly, AX + AW, ly, HEX.accent4, 2, { dashType: "dash" });
  txt(s, "line of visibility — the person sees nothing below this line", { x: AX, y: ly + 0.04, w: AW, h: 0.22, fontSize: 11, italic: true, color: C.accent4, align: "right" });
}

// ---------- 12. Business Capability Map ----------
{
  const s = canvasSlide({ section: S3, n: 8, stage: "What?", name: "Business Capability Map", q: "what must the business be good at — and who does it today?",
    thumb: "capmap", what: "Every ability needed to turn a request into shipped code, done by a person or AIForge.",
    ex: "Of the 18 abilities, AIForge does 11 today and 3 in part. People still decide, accept and measure.",
    short: "11 of 18 done by AIForge today, 3 partly. The rest still needs an owner.",
    notes: "Grey = AIForge does this today. Yellow = partly, being built. White with a dashed edge = still all people. The white boxes are mostly about ownership: prioritising, merging, measuring." });
  const cw = AW / 6;
  const D = "d", P = "p", H = "h";
  const cols = [
    ["Understand the ask", [["Capture a ticket", H], ["Clarify what is wanted", D], ["Prioritise", H]]],
    ["Design the change", [["Read the codebase", D], ["Split the work", D], ["Agree how parts connect", D]]],
    ["Build the change", [["Write the code", D], ["Join files together", D], ["Keep to standards", P]]],
    ["Prove quality", [["Write tests", D], ["Run the build", D], ["Second check", D]]],
    ["Release and run", [["Open a pull request", D], ["Accept the change", H], ["Run the platform", P]]],
    ["Learn and improve", [["Keep lessons", D], ["Share across the team", P], ["Measure use", H]]],
  ];
  const fill = { d: C.accent3, p: C.accent2, h: C.background1 };
  cols.forEach(([head, items], i) => {
    const x = AX + i * cw;
    s.addShape(SH.RECTANGLE, { x, y: AY, w: cw - 0.07, h: 0.68, fill: { color: C.text2 }, rectRadius: 0.06, objectName: "Capability group" });
    txt(s, head, { x: x + 0.06, y: AY, w: cw - 0.19, h: 0.68, fontSize: 12.5, bold: true, color: C.background1, align: "center", valign: "middle" });
    items.forEach(([t, k], j) => cell(s, x, AY + 0.78 + j * 0.85, cw - 0.07, 0.76, null, t, { fill: fill[k], align: "center", fs: 12, lineColor: k === "h" ? HEX.accent6 : HEX.accent3, dash: k === "h" ? "dash" : "solid" }));
  });
  const ly = AY + 0.78 + 3 * 0.85 + 0.12;
  [["AIForge does this today", C.accent3, "solid"], ["Partly — being built", C.accent2, "solid"], ["Still all people", C.background1, "dash"]].forEach(([t, f, d], i) => {
    const x = AX + i * 2.83;
    box(s, x, ly, 0.4, 0.3, { fill: f, dash: d, lineColor: d === "dash" ? HEX.accent6 : HEX.accent3, name: "Legend swatch" });
    txt(s, t, { x: x + 0.5, y: ly, w: 2.25, h: 0.3, fontSize: 12, valign: "middle" });
  });
}

// ---------- 13. Capability Card ----------
{
  const s = canvasSlide({ section: S3, n: 9, stage: "What?", name: "Capability Card", q: "what does one ability need — people, process, tools?",
    thumb: "capcard", what: "One ability taken apart: people, process, tools, and how grown-up it is.",
    ex: "“Build the change” is rated Good: it works on small tickets (3–5 files), not yet on big ones (8–10).",
    short: "to improve: bigger AI models, shared memory, and a named owner for the platform.",
    notes: "This card is for the capability 'Build the change'. Maturity today is Good. The weakest link overall is memory: it works, but sharing it across the team is only now being built." });
  box(s, AX, AY, AW, 1.0, { name: "Capability header" });
  txt(s, [{ text: "BUILD THE CHANGE", options: { fontSize: 11, bold: true, color: C.accent1, breakLine: true } }, { text: "Turn an agreed plan into code that builds and fits the project." }],
    { x: AX + 0.15, y: AY, w: 5.0, h: 1.0, fontSize: 13, valign: "middle" });
  txt(s, "Growing: needs help · Good: small tickets · Strong: big tickets", { x: AX + 4.55, y: AY + 0.71, w: 3.85, h: 0.24, fontSize: 9, italic: true, color: C.accent6, align: "center" });
  txt(s, "HOW GOOD ARE WE AT IT TODAY?", { x: AX + 5.3, y: AY + 0.06, w: 3.0, h: 0.22, fontSize: 10, bold: true, color: C.accent6, align: "center" });
  ["Growing", "Good", "Strong"].forEach((t, i) => {
    const on = i === 1;
    s.addShape(SH.RECTANGLE, { x: AX + 5.3 + i * 1.02, y: AY + 0.31, w: 0.97, h: 0.36, fill: { color: on ? C.accent5 : C.background2 }, rectRadius: 0.06, line: { color: HEX.accent3, width: 1 }, objectName: "Maturity step" });
    txt(s, t, { x: AX + 5.3 + i * 1.02, y: AY + 0.31, w: 0.97, h: 0.36, fontSize: 12, bold: on, color: on ? C.background1 : C.accent6, align: "center", valign: "middle" });
  });
  const cw = (AW - 0.24) / 3, cy = AY + 1.1, ch = 2.0;
  const cols = [
    ["People", "who does it", ["One person runs the platform today", "Senior developer reviews the output", "Nobody owns the AI models yet"], C.accent1],
    ["Process", "how it is done", ["Plan written before any code", "Each part built in its own copy", "Only code that builds is accepted"], C.text2],
    ["Tools", "what it runs on", ["AI models on our own machines", "Code map and OKF memory notes", "Build and test tools already in use"], C.accent5],
  ];
  cols.forEach(([h, hint, items, col], i) => {
    const x = AX + i * (cw + 0.12);
    box(s, x, cy, cw, ch, { name: "Capability column" });
    num(s, x + 0.12, cy + 0.12, i + 1, 0.4, col);
    txt(s, [{ text: h, options: { fontSize: 15, bold: true, color: C.text2 } }, { text: "   " + hint, options: { fontSize: 11, italic: true, color: C.accent6 } }], { x: x + 0.62, y: cy + 0.12, w: cw - 0.75, h: 0.4, valign: "middle" });
    txt(s, items.map((v, j) => ({ text: v, options: { bullet: { indent: 12 }, breakLine: j < items.length - 1 } })), { x: x + 0.14, y: cy + 0.58, w: cw - 0.28, h: ch - 0.62, fontSize: 11.5, paraSpaceAfter: 2 });
  });
  const gy = cy + ch + 0.12, gh = AH - (gy - AY);
  box(s, AX, gy, AW, gh, { fill: TINT.orange, lineColor: HEX.accent4, name: "Gap to target" });
  txt(s, "WHAT IS MISSING (TODAY → WHAT WE WANT)", { x: AX + 0.15, y: gy + 0.07, w: 6, h: 0.26, fontSize: 11, bold: true, color: C.accent4 });
  ["Size: 3–5 files today, 8–10 wanted", "Memory notes not yet shared across the team", "No second person trained yet"].forEach((t, i) => {
    txt(s, t, { x: AX + 0.15 + i * (AW - 0.3) / 3, y: gy + 0.34, w: (AW - 0.3) / 3 - 0.15, h: gh - 0.38, fontSize: 12.5, bold: true, color: C.text1 });
  });
}

pres.addSection({ title: S4 });

// ---------- ASR Card ----------
{
  const s = canvasSlide({ section: S4, n: 10, stage: "How?", name: "ASR Card", q: "which few rules shape the whole design?",
    thumb: "asr", what: "ASR = a must-have rule. Break it and the whole design fails.",
    ex: "Three rules: do the job alone, make the files fit together, stay on our machines.",
    short: "three rules hold up the whole design. Break any one and the tool is not worth using.",
    notes: "ASR stands for architecturally significant requirement. Each card states the rule, how critical it is, what it risks or costs, and the proof that it holds. Picture them as three pillars: take one away and the roof falls. These cards drive the decision record and the QATT card that follow." });
  s.addShape(SH.ISOSCELES_TRIANGLE, { x: AX, y: AY, w: AW, h: 0.42, fill: { color: C.text2 }, objectName: "Roof" });
  s.addShape(SH.RECTANGLE, { x: AX, y: AY + 0.42, w: AW, h: 0.4, fill: { color: C.text2 }, objectName: "Beam" });
  txt(s, "THE WHOLE AIFORGE DESIGN RESTS ON THREE RULES", { x: AX, y: AY + 0.42, w: AW, h: 0.4, fontSize: 12, bold: true, color: C.background1, align: "center", valign: "middle", charSpacing: 1.5 });
  const cw = 2.5, sp = (AW - 3 * cw) / 4, py = AY + 0.82, ph = AH - 0.82 - 0.14;
  s.addShape(SH.RECTANGLE, { x: AX, y: AY + AH - 0.14, w: AW, h: 0.14, fill: { color: C.accent6 }, objectName: "Ground" });
  const asr = [
    ["Do the job on its own", "Ticket in, pull request out. Nobody in the middle.", "RISK", "Bad automatic changes destroy trust fast.", "First full run: ticket to pull request with no help.", "HIGH"],
    ["Make the files fit together", "Change five files and they still build as one.", "RISK", "Big tickets look done but do not build.", "Code across files builds: 0 lines before, 53 after.", "HIGH"],
    ["Stay on our machines", "Machines we own. No cloud. Works offline.", "COST", "Our own models are weaker than cloud ones.", "Zero runs have sent data outside.", "MEDIUM-HIGH"],
  ];
  asr.forEach(([h, b, rl, rk, p, lvl], i) => {
    const x = AX + sp + i * (cw + sp), hi = lvl === "HIGH";
    box(s, x, py, cw, ph, { r: 0.02, name: "Pillar" });
    num(s, x + 0.12, py + 0.1, i + 1, 0.4);
    s.addShape(SH.RECTANGLE, { x: x + cw - 1.97, y: py + 0.14, w: 1.85, h: 0.32, fill: { color: hi ? C.accent4 : C.accent2 }, objectName: "Importance" });
    txt(s, "IMPORTANCE: " + lvl.replace("MEDIUM", "MED"), { x: x + cw - 1.97, y: py + 0.14, w: 1.85, h: 0.32, fontSize: 9.5, bold: true, align: "center", valign: "middle", color: hi ? C.background1 : C.text1 });
    txt(s, h, { x: x + 0.12, y: py + 0.56, w: cw - 0.24, h: 0.52, fontSize: 14.5, bold: true, color: C.text2, valign: "middle" });
    txt(s, b, { x: x + 0.12, y: py + 1.1, w: cw - 0.24, h: 0.5, fontSize: 12 });
    txt(s, [{ text: (rl === "RISK" ? "IF IT BREAKS:" : "THE PRICE:") + "  ", options: { bold: true, color: C.accent4, fontSize: 10.5 } }, { text: rk }], { x: x + 0.12, y: py + 1.62, w: cw - 0.24, h: 0.5, fontSize: 12 });
    box(s, x + 0.1, py + 2.2, cw - 0.2, ph - 2.3, { fill: TINT.green, lineColor: TINT.green, name: "Proof" });
    txt(s, [{ text: "PROOF IT HOLDS:  ", options: { bold: true, color: C.accent5, fontSize: 10.5 } }, { text: p }], { x: x + 0.18, y: py + 2.2, w: cw - 0.36, h: ph - 2.3, fontSize: 11, valign: "middle" });
  });
}

// ---------- 15. QATT Card ----------
{
  const s = canvasSlide({ section: S4, n: 11, stage: "How?", name: "QATT Card", q: "how do we turn “it must be good” into a number?",
    thumb: "qatt", what: "A quality written as a test: who does what, and what we measure.",
    ex: "A five-file ticket must come out as one change that builds. Code that links across files: 0 lines before, 53 after.",
    short: "splitting the work beat waiting for a bigger model — and we have the number to show it.",
    notes: "QATT = quality attribute scenario. The top chain is one scenario in the six standard IASA parts: source, stimulus, environment, artifact, response, response measure. The three cards below are further scenarios in short form. Said out loud: hard compile-and-fix work still needs a human finish." });
  txt(s, [{ text: "SCENARIO   ", options: { bold: true, color: C.accent1, fontSize: 11 } }, { text: "A multi-file ticket comes out as one working change", options: { bold: true, color: C.text2 } }], { x: AX, y: AY, w: AW, h: 0.36, fontSize: 14, valign: "middle" });
  const parts = [["WHO", "A developer or QA engineer"], ["DOES WHAT", "files a ticket that touches five files"], ["WHERE", "a normal day, on our own machines"], ["TO WHAT", "the AIForge agents"], ["RESULT", "one merged change that builds"], ["MEASURE", "cross-file lines that build: 0 → 53"]];
  const pw = AW / 6;
  parts.forEach(([t, b], i) => {
    const last = i === 5;
    s.addShape(i === 0 ? SH.PENTAGON : SH.CHEVRON, { x: AX + i * pw, y: AY + 0.42, w: pw + (last ? 0 : 0.12), h: 0.38, fill: { color: last ? C.accent4 : (i % 2 ? C.accent1 : C.text2) }, objectName: "Scenario part" });
    txt(s, t, { x: AX + i * pw + 0.16, y: AY + 0.42, w: pw - 0.2, h: 0.38, fontSize: 10, bold: true, color: C.background1, align: "center", valign: "middle" });
    cell(s, AX + i * pw + 0.02, AY + 0.86, pw - 0.07, 1.02, null, b, { fs: 12, align: "center", fill: last ? C.accent2 : C.background1, lineColor: last ? HEX.accent4 : HEX.accent3, bold: last });
  });
  txt(s, "MORE SCENARIOS  —  the same idea, written short", { x: AX, y: AY + 2.02, w: AW, h: 0.26, fontSize: 11, bold: true, color: C.accent1 });
  const more = [
    ["Nothing leaves our network", "A check fails the build if it would call out", "Today: working, small batch", C.accent5],
    ["We know the size limit", "Count files one ticket handles cleanly", "Today: 3–5 files", C.accent4],
    ["Memory notes stay few and clean", "Count duplicate notes each week", "Today: merge built, not live", C.accent6],
  ];
  const cw = (AW - 0.24) / 3, my = AY + 2.32, mh = AH - 2.32;
  more.forEach(([h, chk, st, col], i) => {
    const x = AX + i * (cw + 0.12);
    box(s, x, my, cw, mh, { name: "Scenario card" });
    txt(s, h, { x: x + 0.14, y: my + 0.08, w: cw - 0.28, h: 0.5, fontSize: 13, bold: true, color: C.text2, valign: "middle" });
    txt(s, [{ text: "How we check:  ", options: { bold: true, color: C.accent1 } }, { text: chk }], { x: x + 0.14, y: my + 0.64, w: cw - 0.28, h: 0.56, fontSize: 12.5 });
    pill(s, x + 0.14, my + mh - 0.44, cw - 0.28, 0.34, st, col, C.background1);
  });
}

// ---------- 16. Decision Record (ADR) ----------
{
  const s = canvasSlide({ section: S4, n: 12, stage: "How?", name: "Decision Record (ADR)", q: "what did we decide, what else did we consider, and why?",
    thumb: "adr", what: "A short note of one choice: what we picked, what we dropped, and why.",
    ex: "How should agents remember past work? We picked short OKF notes over plain RAG, a graph database, or no memory.",
    short: "small models need less to read, not more. A few short notes beat a big pile of search results.",
    notes: "OKF = Open Knowledge Format (v0.1): a folder of Markdown files, one fact per file, a 'type' at the top (learning, solution, task...), and links between files. AIForge finds the right notes with a small keyword + meaning search (SQLite) and gives each agent only those few. Classic RAG chops all code and documents into pieces and pastes the closest pieces into the prompt: on small local models that floods the 3–5-file window with half-related text. We also tried a graph database (Neo4j) and dropped it: heavy to run and to keep in step with the code. The decision log also holds the earlier choice of many small agents — same reason: keep what each model reads small." });
  cell(s, AX, AY, AW, 0.86, "THE PROBLEM WE HAD", "Agents must remember what worked before: team rules, past fixes, known traps. But our small AI models can only read a little at once — give them too much and they lose the point.", { fs: 12 });
  const ow = (AW - 0.36) / 4, oy = AY + 0.94, oh = 1.42;
  const opts = [
    ["Plain RAG", "Pastes many pieces of code and docs in. Too noisy for small models.", false],
    ["Graph database", "Tried Neo4j. Heavy to run and to keep in step with code.", false],
    ["No memory", "Every run starts from zero and repeats old mistakes.", false],
    ["OKF notes", "Short Markdown notes, one fact each. Only the few that match are read.", true]];
  opts.forEach(([h, b, pick], i) => {
    const x = AX + i * (ow + 0.12);
    box(s, x, oy, ow, oh, { fill: pick ? C.accent1 : C.background1, lineColor: pick ? HEX.accent1 : HEX.accent3, name: "Option" });
    pill(s, x + 0.12, oy + 0.1, 1.05, 0.28, pick ? "CHOSEN" : "REJECTED", pick ? C.accent2 : TINT.orange, pick ? C.text1 : C.accent4);
    txt(s, h, { x: x + 0.12, y: oy + 0.42, w: ow - 0.24, h: 0.3, fontSize: 13.5, bold: true, color: pick ? C.background1 : C.text2 });
    txt(s, b, { x: x + 0.12, y: oy + 0.73, w: ow - 0.24, h: 0.66, fontSize: 11, color: pick ? C.background1 : C.text1 });
  });
  const dy = oy + oh + 0.08, dh = AH - (dy - AY), w1 = 3.05, w2 = 3.05, w3 = AW - w1 - w2 - 0.24;
  cell(s, AX, dy, w1, dh, "OUR DECISION — WE WILL…", "keep memory as short OKF notes, find them with a small keyword + meaning search, and give each agent only the few it needs.", { fill: C.accent2, lineColor: HEX.accent4, lw: 1.5, tcol: C.text2, fs: 11.5, bold: true });
  cell(s, AX + w1 + 0.12, dy, w2, dh, "WHAT IT MEANS FOR US", [
    { text: "+ ", options: { bold: true, color: C.accent5 } }, { text: "anyone can open, read and fix a note; small models stay focused", options: { breakLine: true } },
    { text: "– ", options: { bold: true, color: C.accent4 } }, { text: "notes must be kept tidy: duplicates merged" }], { fs: 11.5 });
  const rx = AX + w1 + w2 + 0.24;
  box(s, rx, dy, w3, dh, { name: "Characteristics" });
  txt(s, "CAN WE UNDO IT?", { x: rx + 0.11, y: dy + 0.07, w: w3 - 0.22, h: 0.26, fontSize: 11, bold: true, color: C.accent1 });
  seg(s, rx + 0.2, dy + 0.5, rx + w3 - 0.2, dy + 0.5, HEX.accent3, 4);
  s.addShape(SH.OVAL, { x: rx + 0.42, y: dy + 0.39, w: 0.22, h: 0.22, fill: { color: C.accent5 }, objectName: "Reversibility marker" });
  txt(s, "easy to undo", { x: rx + 0.11, y: dy + 0.62, w: w3 / 2, h: 0.22, fontSize: 10, color: C.accent6 });
  txt(s, "permanent", { x: rx + w3 / 2, y: dy + 0.62, w: w3 / 2 - 0.11, h: 0.22, fontSize: 10, color: C.accent6, align: "right" });
  txt(s, [{ text: "Plain files: easy to move to another store.", options: { breakLine: true } }, { text: "Owner: ", options: { bold: true } }, { text: "project lead" }], { x: rx + 0.11, y: dy + 0.86, w: w3 - 0.22, h: dh - 0.9, fontSize: 10.5 });
}

pres.addSection({ title: S5 });

// ---------- 17. OKR Card ----------
{
  const s = canvasSlide({ section: S5, n: 13, stage: "Where next?", name: "OKR Card", q: "what does good look like, in numbers we can check?",
    thumb: "okr", what: "OKR = one goal, and a few numbers that show progress.",
    ex: "Goal: small tickets go through AIForge by default. The key number, how many of its pull requests get accepted, is not counted yet.",
    short: "the tool works; now we must measure how often it succeeds. The first row is the problem.",
    notes: "Without the first number there is no case to make this standard practice. Bars show how far today is from target; the dashed bar means we do not measure it yet." });
  s.addShape(SH.RECTANGLE, { x: AX, y: AY, w: AW, h: 0.68, fill: { color: C.text2 }, rectRadius: 0.08, objectName: "Objective" });
  txt(s, [{ text: "GOAL   ", options: { bold: true, color: C.accent2, fontSize: 11 } }, { text: "Make AIForge the normal way small work gets done", options: { bold: true, color: C.background1 } }], { x: AX + 0.2, y: AY, w: AW - 0.4, h: 0.68, fontSize: 16, valign: "middle" });
  const kx = AX, kw = 4.3, bx = AX + 4.4, bw = 1.75, tx = bx + bw + 0.15, tw = 1.15, gx2 = tx + tw + 0.05, gw = AX + AW - gx2;
  const hy = AY + 0.76;
  [["WHAT WE COUNT, AND WHY", kx, kw, "left"], ["HOW CLOSE WE ARE", bx, bw, "left"], ["TODAY", tx, tw, "center"], ["TARGET", gx2, gw, "center"]].forEach(([t, x, w, a]) => txt(s, t, { x, y: hy, w, h: 0.24, fontSize: 10, bold: true, color: C.accent6, align: a }));
  const krs = [
    ["Accepted pull requests", "of the tickets it takes, how many a person accepts", null, "Not counted", "3 in 4", C.accent4],
    ["Files one ticket can change", "bigger = it can take bigger tickets", 0.45, "3 to 5", "8 to 10", C.accent4],
    ["Tickets from juniors and QA", "shows it is used beyond the seniors", 0.06, "Almost none", "Half", C.accent4],
    ["People who can run it", "so it does not hang on one person", 0.5, "1", "2", C.accent4],
    ["Runs that sent data outside", "our hard rule: must stay zero", 1, "Zero", "Zero", C.accent5],
  ];
  const ry = hy + 0.28, pitch = (AY + AH - ry) / 5;
  krs.forEach(([t, why, pct, now, tgt, col], i) => {
    const y = ry + i * pitch, h = pitch - 0.07;
    box(s, kx, y, AW, h, { name: "Key result row" });
    txt(s, [{ text: t, options: { bold: true, breakLine: true } }, { text: why, options: { fontSize: 10.5, color: C.accent6 } }], { x: kx + 0.14, y, w: kw - 0.2, h, fontSize: 12.5, valign: "middle" });
    const by = y + h / 2 - 0.11;
    s.addShape(SH.RECTANGLE, { x: bx, y: by, w: bw, h: 0.22, fill: { color: C.background2 }, rectRadius: 0.11, line: { color: HEX.accent6, width: 1, dashType: pct === null ? "dash" : "solid" }, objectName: "Progress track" });
    if (pct) s.addShape(SH.RECTANGLE, { x: bx, y: by, w: Math.max(bw * pct, 0.22), h: 0.22, fill: { color: col }, rectRadius: 0.11, objectName: "Progress" });
    txt(s, now, { x: tx, y, w: tw, h, fontSize: 12.5, bold: true, color: col, align: "center", valign: "middle" });
    txt(s, tgt, { x: gx2, y, w: gw - 0.1, h, fontSize: 12.5, bold: true, color: C.text2, align: "center", valign: "middle" });
  });
}

// ---------- 18. Roadmap Canvas ----------
{
  const s = canvasSlide({ section: S5, n: 14, stage: "Where next?", name: "Roadmap Canvas", q: "what happens when — for product, platform and people?",
    thumb: "roadmap", what: "The plan over time: product, platform and people together.",
    ex: "From an honest result on every pull request now, to open for every team by the end of the year.",
    short: "one rule for the whole year: nothing on this plan moves work off our own machines.",
    notes: "Read each row left to right. The people row is the one most likely to slip, and it is the one the power/interest grid said matters most." });
  const lw = 1.3, cw = (AW - lw) / 4, x0 = AX + lw;
  ["Q1", "Q2", "Q3", "Q4"].forEach((q, i) => {
    s.addShape(i === 0 ? SH.PENTAGON : SH.CHEVRON, { x: x0 + i * cw, y: AY, w: cw + (i < 3 ? 0.1 : -0.03), h: 0.5, fill: { color: i % 2 ? C.accent1 : C.text2 }, objectName: "Quarter" });
    txt(s, q, { x: x0 + i * cw, y: AY, w: cw, h: 0.5, fontSize: 15, bold: true, color: C.background1, align: "center", valign: "middle" });
  });
  const rows = [
    ["Product", "what users get", ["Honest result on every pull request", "Team memory sharing live", "Bigger tickets, more files", "Open to every team"], C.accent1, TINT.teal],
    ["Platform", "machines and models", ["Bigger machines planned", "Bigger AI models tested", "IT runs the AI models", "Machine needs planned ahead"], C.accent4, TINT.orange],
    ["People", "who owns and uses it", ["Second person named", "QA owns the test check", "Juniors start using it", "Use measured every month"], C.accent5, TINT.green],
  ];
  const ry = AY + 0.6, pitch = (AH - 0.6) / 3;
  rows.forEach(([label, hint, vals, col, fill], r) => {
    const y = ry + r * pitch, h = pitch - 0.1;
    s.addShape(SH.RECTANGLE, { x: AX, y, w: lw - 0.1, h, fill: { color: col }, rectRadius: 0.08, objectName: "Row label" });
    txt(s, [{ text: label, options: { fontSize: 15, bold: true, breakLine: true } }, { text: hint, options: { fontSize: 10 } }], { x: AX + 0.04, y, w: lw - 0.18, h, color: C.background1, align: "center", valign: "middle" });
    vals.forEach((v, i) => cell(s, x0 + i * cw, y, cw - 0.07, h, null, v, { fill, lineColor: fill, align: "center", fs: 13 }));
  });
}

// =====================================================================
// PART 3 — wrap-up
// =====================================================================
pres.addSection({ title: S6 });

// ---------- 19. How the canvases connect ----------
{
  const s = content(S6, "How the canvases connect", "One thread through six canvases — each claim has a canvas behind it");
  sticky(s, "The thread", "Cause and effect");
  const chain = [
    ["Persona Card", "“I know how to do this. I do not have the hours.”"],
    ["Customer Journey", "The wait is the cost, not the typing."],
    ["ASR Card", "So it must do the job on its own."],
    ["Decision Record", "So each agent reads little: small jobs, short notes."],
    ["QATT Card", "Proof: code across files now builds (0 → 53 lines)."],
    ["OKR Card", "Next: 3 in 4 tickets accepted."],
  ];
  const w = 1.72, gap = (12.13 - 6 * w) / 5;
  chain.forEach(([c, t], i) => {
    const x = 0.6 + i * (w + gap), rot = i % 2 ? -1.5 : 1.5;
    pill(s, x, 2.0, w, 0.36, c, i % 2 ? C.accent1 : C.text2, C.background1);
    s.addShape(SH.RECTANGLE, { x, y: 2.6, w, h: 1.85, fill: { color: C.accent2 }, objectName: "Sticky note" });
    txt(s, t, { x: x + 0.12, y: 2.6, w: w - 0.24, h: 1.85, fontSize: 14, bold: true, color: C.text1, align: "center", valign: "middle" });
    if (i < 5) arrow(s, x + w + gap / 2 - 0.15, 3.38, 0.3, 0.3, C.accent4);
  });
  const labels = ["person", "pain", "requirement", "decision", "proof", "goal"];
  labels.forEach((l, i) => txt(s, l, { x: 0.6 + i * (w + gap), y: 4.62, w, h: 0.3, fontSize: 13, italic: true, color: C.accent6, align: "center" }));
  box(s, 0.6, 5.1, 12.13, 0.8, { name: "Reading tip" });
  txt(s, [{ text: "Why this matters:  ", options: { bold: true, color: C.text2 } }, { text: "change one note and you know which others to revisit. That is the link a long document hides." }],
    { x: 0.85, y: 5.1, w: 11.6, h: 0.8, fontSize: 15, valign: "middle" });
  inShort(s, "the canvases are not fourteen documents. They are one argument on fourteen pages.");
  s.addNotes("This is the traceability the toolkit talks about: the persona's pain becomes a requirement, the requirement forces a decision, the decision is proved by a measured scenario, and the goal tracks it over time.");
}

// ---------- Take away ----------
{
  const s = content(S6, "What to take away", "Four steps to use the canvases on your own work");
  const steps = [["Start with the person", "not with the technology"], ["One page each", "if it does not fit, it is not clear yet"], ["Fill in facts", "and leave the gaps where all can see"], ["Follow the links", "pin them side by side"]];
  const w = 2.7, gap = (12.13 - 4 * w) / 3;
  steps.forEach(([h, b], i) => {
    const x = 0.6 + i * (w + gap);
    box(s, x, 1.95, w, 1.5, { name: "Step" });
    num(s, x + 0.1, 2.05, i + 1, 0.5);
    txt(s, h, { x: x + 0.65, y: 2.05, w: w - 0.8, h: 0.5, fontSize: 16, bold: true, valign: "middle" });
    txt(s, b, { x: x + 0.2, y: 2.65, w: w - 0.4, h: 0.7, fontSize: 14 });
    if (i < 3) arrow(s, x + w + gap / 2 - 0.15, 2.55, 0.3, 0.3, C.accent6);
  });
  txt(s, "What AIForge taught us", { x: 0.6, y: 3.85, w: 12, h: 0.4, fontSize: 18, bold: true });
  const notes = ["The limit was the design, not the model.", "One page per canvas made the thinking easy to check.", "A tool one person can run is not yet a tool the company owns."];
  const nw = 3.85, ng = (12.13 - 3 * nw) / 2;
  notes.forEach((t, i) => {
    const x = 0.6 + i * (nw + ng);
    box(s, x, 4.4, nw, 1.2, { fill: C.accent2, lineColor: LINE, name: "Lesson" });
    txt(s, t, { x: x + 0.2, y: 4.4, w: nw - 0.4, h: 1.2, fontSize: 15, valign: "middle" });
  });
  inShort(s, "every claim here has a canvas behind it.");
  s.addNotes("Close by asking the audience to pick one canvas and fill it for their own project this week. The persona card is the easiest place to start.");
}

(async () => {
  const out = process.argv[2] || "IASA-Canvases-with-AIForge.pptx";
  await pres.writeFile({ fileName: out });
  await applyTheme(out, THEME);
  console.log("wrote", out);
})();
