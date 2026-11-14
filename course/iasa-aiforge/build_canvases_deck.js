// IASA canvases explained with AIForge: how canvases help, the canvas map,
// then each canvas drawn in its own shape and filled in for AIForge.
const pptxgen = require("pptxgenjs");
const { applyTheme } = require(process.env.SKILL + "/apply_theme.js");

const THEME = {
  name: "AIForge Teal",
  headFontFace: "Cambria",
  bodyFontFace: "Calibri",
  colors: {
    dk1: "1B2A30", lt1: "FFFFFF", dk2: "1F4E5F", lt2: "EEF4F6",
    accent1: "2E7D8C", accent2: "FBE7A1", accent3: "C8DDE3", accent4: "D9822B",
    accent5: "5B8C5A", accent6: "6B7D84", hlink: "2E7D8C", folHlink: "1F4E5F",
  },
};
const HEX = THEME.colors;
const TINT = { orange: "F6E3D3", green: "DCEEE2", teal: "E3F1F3" };
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
  background: { color: C.text2 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.8, y: 1.9, w: 11.7, h: 1.5, fontSize: 50, bold: true, color: C.background1, fontFace: THEME.headFontFace, valign: "bottom", align: "left", margin: 0 }, text: "" } },
    { placeholder: { options: { name: "body", type: "body", x: 0.8, y: 3.55, w: 11.0, h: 1.4, fontSize: 24, color: C.accent3, valign: "top", align: "left", margin: 0 }, text: "" } },
  ],
});
pres.defineSlideMaster({
  title: "CONTENT",
  background: { color: C.background2 },
  margin: [0.5, 0.6, 0.6, 0.6],
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.6, y: 0.4, w: 9.6, h: 0.8, fontSize: 36, bold: true, color: C.text2, fontFace: THEME.headFontFace, valign: "middle", align: "left", margin: 0 }, text: "" } },
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
// sticky note, top right: the deck's motif
function sticky(s, small, big) {
  s.addShape(SH.RECTANGLE, { x: 10.55, y: 0.4, w: 2.2, h: 0.85, fill: { color: C.accent2 }, rotate: 2,
    shadow: { type: "outer", color: HEX.accent6, opacity: 0.35, blur: 4, offset: 2, angle: 90 }, objectName: "Sticky note" });
  txt(s, [{ text: small, options: { fontSize: 11, color: C.accent6, breakLine: true } }, { text: big, options: { fontSize: 14, bold: true, color: C.text1 } }],
    { x: 10.6, y: 0.42, w: 2.1, h: 0.8, align: "center", valign: "middle", rotate: 2 });
}
function inShort(s, text) {
  s.addShape(SH.ROUNDED_RECTANGLE, { x: 0.6, y: 6.15, w: 12.13, h: 0.7, fill: { color: C.text2 }, rectRadius: 0.08, objectName: "In short band" });
  txt(s, [{ text: "In short:  ", options: { bold: true, color: C.accent2 } }, { text, options: { color: C.background1 } }],
    { x: 0.85, y: 6.15, w: 11.7, h: 0.7, fontSize: 18, valign: "middle" });
}
function box(s, x, y, w, h, o = {}) {
  s.addShape(SH.ROUNDED_RECTANGLE, { x, y, w, h, fill: { color: o.fill || C.background1 }, rectRadius: o.r === undefined ? 0.07 : o.r,
    line: { color: o.lineColor || HEX.accent3, width: o.lw || 1, dashType: o.dash || "solid" }, objectName: o.name || "Box" });
}
// a canvas cell: small caption on top, content below
function cell(s, x, y, w, h, title, body, o = {}) {
  box(s, x, y, w, h, o);
  const pad = 0.11;
  let ty = y + 0.07;
  if (title) { txt(s, title, { x: x + pad, y: ty, w: w - 2 * pad, h: 0.26, fontSize: o.tfs || 11, bold: true, color: o.tcol || C.accent1 }); ty += 0.29; }
  if (body) txt(s, body, { x: x + pad, y: title ? ty : y, w: w - 2 * pad, h: title ? y + h - ty - 0.05 : h, fontSize: o.fs || 12,
    color: o.col || C.text1, valign: title ? "top" : "middle", align: o.align || "left", bold: !!o.bold });
}
function num(s, x, y, n, d = 0.5, fill) {
  s.addShape(SH.OVAL, { x, y, w: d, h: d, fill: { color: fill || C.accent1 }, objectName: "Number circle" });
  txt(s, String(n), { x, y, w: d, h: d, align: "center", valign: "middle", fontSize: d > 0.45 ? 18 : 12, bold: true, color: C.background1 });
}
function arrow(s, x, y, w = 0.35, h = 0.35, fill) { s.addShape(SH.RIGHT_ARROW, { x, y, w, h, fill: { color: fill || C.accent1 }, objectName: "Arrow" }); }
function pill(s, x, y, w, h, text, fill, col) {
  s.addShape(SH.ROUNDED_RECTANGLE, { x, y, w, h, fill: { color: fill }, rectRadius: h / 2, objectName: "Pill" });
  txt(s, text, { x, y, w, h, fontSize: 11, bold: true, align: "center", valign: "middle", color: col || C.text1 });
}
function person(s, x, y, d) { // simple avatar: circle, head, shoulders
  s.addShape(SH.OVAL, { x, y, w: d, h: d, fill: { color: C.accent3 }, objectName: "Avatar" });
  s.addShape(SH.OVAL, { x: x + d * 0.34, y: y + d * 0.18, w: d * 0.32, h: d * 0.32, fill: { color: C.text2 }, objectName: "Avatar head" });
  s.addShape(SH.ROUNDED_RECTANGLE, { x: x + d * 0.22, y: y + d * 0.56, w: d * 0.56, h: d * 0.28, fill: { color: C.text2 }, rectRadius: d * 0.12, objectName: "Avatar shoulders" });
}
function seg(s, x1, y1, x2, y2, color, width, o = {}) { // straight line between two points
  s.addShape(SH.LINE, { x: Math.min(x1, x2), y: Math.min(y1, y2), w: Math.abs(x2 - x1), h: Math.abs(y2 - y1), flipV: (y2 < y1) !== (x2 < x1),
    line: Object.assign({ color, width: width || 2 }, o), objectName: "Line" });
}

// canvas slide frame: left = what the canvas is, right = the canvas itself filled for AIForge
const AX = 4.25, AY = 1.9, AW = 8.48, AH = 4.05;
function canvasSlide(o) {
  const s = content(o.section, o.name, [{ text: "It answers:  ", options: { bold: true, color: C.accent1 } }, { text: o.q }]);
  sticky(s, o.stage, `Canvas ${o.n} of ${TOTAL}`);
  s.addShape(SH.ROUNDED_RECTANGLE, { x: 0.6, y: AY, w: 3.4, h: AH, fill: { color: C.text2 }, rectRadius: 0.1, objectName: "About the canvas" });
  txt(s, "WHAT IT IS", { x: 0.85, y: AY + 0.2, w: 2.9, h: 0.28, fontSize: 11, bold: true, color: C.accent2, charSpacing: 1.5 });
  txt(s, o.what, { x: 0.85, y: AY + 0.5, w: 2.9, h: 0.95, fontSize: 15, color: C.background1 });
  txt(s, "HOW IT HELPS", { x: 0.85, y: AY + 1.55, w: 2.9, h: 0.28, fontSize: 11, bold: true, color: C.accent2, charSpacing: 1.5 });
  txt(s, o.helps.map((t, i) => ({ text: t, options: { bullet: { indent: 14 }, breakLine: i < o.helps.length - 1 } })),
    { x: 0.85, y: AY + 1.85, w: 2.9, h: 2.05, fontSize: 14, color: C.background1, paraSpaceAfter: 6 });
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
  txt(s, "IASA Masterclass  ·  Canvas guide", { x: 0.8, y: 0.7, w: 8, h: 0.4, fontSize: 16, color: C.accent2, bold: true });
  s.addText("IASA canvases, explained with AIForge", { placeholder: "title" });
  s.addText([
    { text: "What each canvas is for — and the same canvas filled in for our own AI developer.", options: {} },
  ], { placeholder: "body" });
  [["First", "how canvases help"], ["Then", `${TOTAL} canvases, one by one`], ["Each time", "the AIForge example"]].forEach(([a, b], i) => {
    const x = 0.8 + i * 3.0;
    s.addShape(SH.RECTANGLE, { x, y: 5.15, w: 2.6, h: 1.05, fill: { color: C.accent2 }, rotate: i === 1 ? -1.5 : 1.5,
      shadow: { type: "outer", color: "0F2A33", opacity: 0.4, blur: 5, offset: 3, angle: 90 }, objectName: "Sticky note" });
    txt(s, [{ text: a, options: { fontSize: 12, color: C.accent6, breakLine: true } }, { text: b, options: { fontSize: 16, bold: true, color: C.text1 } }],
      { x: x + 0.1, y: 5.15, w: 2.4, h: 1.05, align: "center", valign: "middle", rotate: i === 1 ? -1.5 : 1.5 });
  });
  txt(s, "Roles only — no names, no customer detail.", { x: 0.8, y: 6.75, w: 8, h: 0.35, fontSize: 12, italic: true, color: C.accent3 });
  s.addNotes("This deck teaches the IASA canvases using one running example: AIForge, the tool that turns a ticket into a tested pull request on machines we own. First we look at why canvases help at all, then at each canvas in turn.");
}

// ---------- 2. How canvases help ----------
{
  const s = content(S1, "How canvases help", "Six reasons to fill a one-page canvas instead of writing a long document");
  sticky(s, "Start here", "Why bother?");
  const items = [
    ["One page, not a document", "A single page gets read and kept up to date. A fifty-page document does neither."],
    ["A picture beats a paragraph", "Words alone are ambiguous. A box you must fill forces a clear answer."],
    ["Everyone works on one wall", "Print it, pin it up, fill it with sticky notes. The whole team sees the same thing."],
    ["Each canvas feeds the next", "The persona drives the journey; the journey drives the requirements. Cause and effect."],
    ["Decisions stay traceable", "Requirement, decision, measure — linked. Nobody re-argues the choice next year."],
    ["Gaps show up early", "An empty box is a question nobody has answered yet. Better found now than in the build."],
  ];
  items.forEach(([h, b], i) => {
    const col = i % 3, row = Math.floor(i / 3);
    const x = 0.6 + col * 4.13, y = 1.95 + row * 2.03;
    box(s, x, y, 3.83, 1.83, { name: "Reason card" });
    num(s, x + 0.25, y + 0.25, i + 1, 0.55, row === 0 ? C.accent1 : C.accent4);
    txt(s, h, { x: x + 0.95, y: y + 0.22, w: 2.7, h: 0.6, fontSize: 18, bold: true, color: C.text2, valign: "middle" });
    txt(s, b, { x: x + 0.25, y: y + 0.92, w: 3.35, h: 0.85, fontSize: 14 });
  });
  inShort(s, "a canvas is a one-page question sheet. Fill the boxes and the argument can be checked.");
  s.addNotes("These six points come from the IASA toolkit lesson: least documentation, visual thinking, facilitation on a wall, connected concepts, decision traceability, and finding structural problems early.");
}

// ---------- 3. The canvases at a glance ----------
const STAGES = [
  ["Why?", "the business", ["Business Model Canvas"]],
  ["Who?", "the people", ["Persona Card", "Customer Journey Map", "Power / Interest Grid"]],
  ["What?", "the service", ["Use Case Card", "Context View", "Service Blueprint", "Capability Map", "Capability Card"]],
  ["How?", "the design", ["ASR Card", "QATT Card", "Decision Record (ADR)"]],
  ["Where next?", "the plan", ["OKR Card", "Roadmap Canvas"]],
];
{
  const s = content(S1, "The canvases at a glance", `${TOTAL} canvases, grouped by the question each one answers`);
  sticky(s, "The map", "Five questions");
  let n = 0;
  const w = 2.3, gap = 0.1575;
  STAGES.forEach(([q, cap, list], i) => {
    const x = 0.6 + i * (w + gap);
    s.addShape(SH.PENTAGON, { x, y: 1.95, w, h: 0.85, fill: { color: i % 2 ? C.accent1 : C.text2 }, objectName: "Stage" });
    txt(s, [{ text: q, options: { fontSize: 20, bold: true, breakLine: true } }, { text: cap, options: { fontSize: 12 } }],
      { x: x + 0.15, y: 1.95, w: w - 0.55, h: 0.85, color: C.background1, valign: "middle" });
    list.forEach((name, j) => {
      n += 1;
      const y = 3.0 + j * 0.58;
      box(s, x, y, w, 0.48, { name: "Canvas chip" });
      num(s, x + 0.08, y + 0.07, n, 0.34);
      txt(s, name, { x: x + 0.5, y, w: w - 0.58, h: 0.48, fontSize: 13, bold: true, color: C.text2, valign: "middle" });
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
    ["AIForge", "A small team of AI agents on our own GPUs plans, writes, tests and reviews the change", C.accent1, C.background1],
    ["A pull request", "A tested, reviewed code change, ready for a person to read and merge", C.background1, C.text2],
  ];
  boxes.forEach(([h, b, fill, col], i) => {
    const x = 0.6 + i * 4.2;
    s.addShape(SH.ROUNDED_RECTANGLE, { x, y: 1.95, w: 3.6, h: 2.1, fill: { color: fill }, rectRadius: 0.1, line: { color: HEX.accent3, width: 1 }, objectName: "Flow box" });
    txt(s, h, { x: x + 0.3, y: 2.15, w: 3.0, h: 0.6, fontSize: 26, bold: true, color: col });
    txt(s, b, { x: x + 0.3, y: 2.8, w: 3.0, h: 1.2, fontSize: 16, color: col });
    if (i < 2) arrow(s, x + 3.68, 2.78, 0.45, 0.45);
  });
  const facts = [["Our machines only", "No cloud. No code or data leaves the building."], ["Seven small agents", "Each has one small job and only the context it needs."], ["A person acts twice", "Write the ticket. Read the pull request."]];
  facts.forEach(([h, b], i) => {
    const x = 0.6 + i * 4.2;
    box(s, x, 4.35, 3.6, 1.55, { fill: C.accent2, lineColor: HEX.accent2, name: "Fact card" });
    txt(s, h, { x: x + 0.3, y: 4.5, w: 3.0, h: 0.45, fontSize: 18, bold: true, color: C.text2 });
    txt(s, b, { x: x + 0.3, y: 4.97, w: 3.0, h: 0.85, fontSize: 14 });
  });
  inShort(s, "keep this picture in mind — every canvas that follows describes it from a different side.");
  s.addNotes("AIForge works in a defence setting where cloud AI is not allowed, so it runs on hardware we own. That one fact shows up on almost every canvas.");
}

// =====================================================================
// PART 2 — canvases
// =====================================================================
pres.addSection({ title: S2 });

// ---------- 5. Business Model Canvas ----------
{
  const s = canvasSlide({ section: S2, n: 1, stage: "Why?", name: "Business Model Canvas", q: "how does this create value, and for whom?",
    what: "Nine boxes that show how a product or service earns its keep.",
    helps: ["The whole business case on one page", "Shows who benefits and what it costs", "Starts the chain: segments become personas"],
    short: "AIForge sells nothing. It gives senior hours back, inside our own walls.",
    notes: "This is the internal-product view of the business model: the 'customers' are our own engineers and the 'revenue' is time handed back. No customer or programme detail is shown, on purpose." });
  const cw = AW / 5, g = 0.07, top = 2.72, hh = (top - g) / 2;
  const B = (i, y, h, t, b, o) => cell(s, AX + i * cw, y, cw - g, h, t, b, o);
  B(0, AY, top, "KEY PARTNERS", lines(["IT operations", "QA and testers"]));
  B(1, AY, hh, "KEY ACTIVITIES", "Plan, write, test, review");
  B(1, AY + hh + g, hh, "KEY RESOURCES", lines(["Our own GPUs", "Local models", "Run memory"]));
  B(2, AY, top, "VALUE OFFERED", lines(["Ticket in, tested pull request out.", "", "Code never leaves the building."]), { fill: C.accent2, lineColor: HEX.accent4, lw: 1.5, fs: 13, bold: true, tcol: C.text2 });
  B(3, AY, hh, "RELATIONSHIP", "An honest verdict on every pull request");
  B(3, AY + hh + g, hh, "CHANNELS", lines(["Chat", "Ticket tracker"]));
  B(4, AY, top, "WHO IT SERVES", lines(["Delivery engineers", "Junior developers", "Engineering leads"]));
  const by = AY + top + g, bh = AH - top - g, half = AW / 2;
  cell(s, AX, by, half - g, bh, "WHAT IT COSTS", "GPUs, model calls, and one operator to run the platform", { fill: TINT.orange, tcol: C.accent4 });
  cell(s, AX + half, by, half - g, bh, "WHAT COMES BACK", "Senior hours freed for the hard work; more delivered by the same team", { fill: TINT.green, tcol: C.accent5 });
}

// ---------- 6. Persona Card ----------
{
  const s = canvasSlide({ section: S2, n: 2, stage: "Who?", name: "Persona Card", q: "who exactly are we building for?",
    what: "A one-page picture of one real kind of user, in their own words.",
    helps: ["Stops “the user” meaning everyone", "Their objection is part of the person", "Drives the journey and the requirements"],
    short: "it is built for the delivery engineer. If their day does not change, nothing else matters.",
    notes: "Three personas exist: delivery engineer (primary), junior developer, engineering lead. Only the primary one is drawn. Honest adoption test: do they file a ticket, or still walk over to a senior? Today, mostly the second." });
  box(s, AX, AY, AW, AH, { name: "Persona card" });
  person(s, AX + 0.6, AY + 0.3, 1.3);
  pill(s, AX + 0.45, AY + 1.75, 1.6, 0.32, "PRIMARY PERSONA", C.accent1, C.background1);
  txt(s, "Delivery engineer", { x: AX + 0.1, y: AY + 2.15, w: 2.3, h: 0.4, fontSize: 15, bold: true, color: C.text2, align: "center" });
  txt(s, "“Half my week goes on work I already know how to do.”", { x: AX + 0.2, y: AY + 2.6, w: 2.1, h: 1.3, fontSize: 14, italic: true, color: C.accent1, align: "center" });
  const qx = AX + 2.55, qw = (AW - 2.55 - 0.2 - 0.1) / 2, qh = (AH - 0.4 - 0.1) / 2;
  const Q = [
    ["THEIR DAY", ["Owns a slice of a live system", "Three to six small tickets a week", "Interrupted often; deep work is rare"], C.background2, C.accent1],
    ["WHAT THEY WANT", ["Boilerplate and glue done for them", "Keep the interesting design work", "Never hand code to an outside service"], TINT.green, C.accent5],
    ["WHAT BLOCKS THEM", ["A pull request they do not trust", "A tool that half-finishes and stays quiet", "Setup work before the tool is useful"], TINT.orange, C.accent4],
    ["WHAT EARNS TRUST", ["It compiles, or it says it failed", "“I could not do this” in the first line", "A second model checked the work"], TINT.teal, C.accent1],
  ];
  Q.forEach(([t, items, fill, tcol], i) => {
    cell(s, qx + (i % 2) * (qw + 0.1), AY + 0.2 + Math.floor(i / 2) * (qh + 0.1), qw, qh, t,
      items.map((v, j) => ({ text: v, options: { bullet: { indent: 12 }, breakLine: j < items.length - 1 } })), { fill, tcol, fs: 12.5 });
  });
}

// ---------- 7. Customer Journey Map ----------
{
  const s = canvasSlide({ section: S2, n: 3, stage: "Who?", name: "Customer Journey Map", q: "where does the person wait, and how does it feel?",
    what: "The steps a person goes through, with how each step feels.",
    helps: ["Finds the wait, not just the step", "Before and after sit side by side", "Shows the moment that matters"],
    short: "the cost was never the typing — it was the waiting. AIForge removes the wait.",
    notes: "Read the orange line first (today), then the green one (with AIForge). The person now joins at the pull request, not before it." });
  const lw = 1.3, cw = (AW - lw) / 5, x0 = AX + lw;
  const steps = ["Ticket raised", "Picked up", "Code written", "Tested, reviewed", "Merged"];
  const today = ["sits in the backlog", "waits for a senior to be free", "squeezed between other work", "rushed at the end", "days after it was raised"];
  const after = ["picked up as written", "a run starts, nobody waits", "agents write it in a copy of the code", "tests first, second model reviews", "pull request ready to read"];
  steps.forEach((st, i) => {
    s.addShape(SH.CHEVRON, { x: x0 + i * cw, y: AY, w: cw - 0.03, h: 0.5, fill: { color: C.text2 }, objectName: "Step" });
    txt(s, st, { x: x0 + i * cw + 0.22, y: AY, w: cw - 0.47, h: 0.5, fontSize: 11, bold: true, color: C.background1, align: "center", valign: "middle" });
  });
  // feeling curve
  const fy = AY + 0.6, fh = 1.15;
  box(s, x0, fy, AW - lw - 0.03, fh, { name: "Feeling band" });
  txt(s, [{ text: "How it feels", options: { bold: true, breakLine: true } }, { text: "good at the top", options: { fontSize: 11, color: C.accent6 } }], { x: AX, y: fy, w: lw - 0.1, h: fh, fontSize: 13, color: C.text2, valign: "middle" });
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
    s.addShape(SH.ROUNDED_RECTANGLE, { x: AX, y, w: lw - 0.1, h: 1.0, fill: { color: col }, rectRadius: 0.08, objectName: "Row label" });
    txt(s, label, { x: AX + 0.05, y, w: lw - 0.2, h: 1.0, fontSize: 14, bold: true, color: C.background1, align: "center", valign: "middle" });
    vals.forEach((v, i) => cell(s, x0 + i * cw, y, cw - 0.07, 1.0, null, v, { fill, lineColor: fill, align: "center", fs: 12 }));
  });
}

// ---------- 8. Power / Interest Grid ----------
{
  const s = canvasSlide({ section: S2, n: 4, stage: "Who?", name: "Power / Interest Grid", q: "who must we win over, and who must own it?",
    what: "A two-by-two: each group placed by its say and its stake.",
    helps: ["Shows where each group stands today", "Arrows show where they need to be", "Turns “people issues” into named moves"],
    short: "the tool works. What is left is people — three jobs still have no owner.",
    notes: "Positions are our reading of where each group stands today; the arrows are the moves the roadmap needs. IT operations must go from watching to owning the model service; QA must own the test gate on AI pull requests; the platform needs a second operator." });
  const gx = AX + 0.45, gy = AY, gw = 5.3, gh = 3.6, qw = gw / 2, qh = gh / 2;
  const quad = [["Keep satisfied", 0, 0, C.background1], ["Manage closely", 1, 0, TINT.teal], ["Monitor", 0, 1, C.background1], ["Keep informed", 1, 1, C.background1]];
  quad.forEach(([t, cx, cy, fill]) => {
    s.addShape(SH.RECTANGLE, { x: gx + cx * qw, y: gy + cy * qh, w: qw, h: qh, fill: { color: fill }, line: { color: HEX.accent3, width: 1 }, objectName: "Quadrant" });
    txt(s, t, { x: gx + cx * qw + 0.1, y: gy + cy * qh + (cy ? qh - 0.32 : 0.06), w: qw - 0.2, h: 0.26, fontSize: 11, italic: true, color: C.accent6, align: cx ? "right" : "left" });
  });
  txt(s, "POWER  →", { x: AX - 1.55, y: gy + gh / 2 - 0.15, w: 3.6, h: 0.3, fontSize: 11, bold: true, color: C.text2, align: "center", valign: "middle", rotate: 270, charSpacing: 1.5 });
  txt(s, "INTEREST  →", { x: gx, y: gy + gh + 0.08, w: gw, h: 0.3, fontSize: 11, bold: true, color: C.text2, align: "center", charSpacing: 1.5 });
  const chip = (t, x, y, w, fill, col) => pill(s, gx + x, gy + y, w, 0.4, t, fill, col);
  chip("IT operations", 0.3, 0.42, 1.5, C.accent4, C.background1);
  seg(s, gx + 1.85, gy + 0.62, gx + 3.15, gy + 0.62, HEX.accent4, 2, { dashType: "dash", endArrowType: "triangle" });
  chip("Engineering lead", 3.3, 0.42, 1.75, C.text2, C.background1);
  chip("Platform operator", 3.3, 1.2, 1.75, C.text2, C.background1);
  chip("Delivery engineers", 2.78, 2.25, 1.75, C.accent1, C.background1);
  chip("QA and testers", 3.45, 2.88, 1.6, C.accent4, C.background1);
  seg(s, gx + 4.85, gy + 2.83, gx + 4.85, gy + 1.92, HEX.accent4, 2, { dashType: "dash", endArrowType: "triangle" });
  chip("Junior developers", 0.55, 2.55, 1.75, C.accent1, C.background1);
  const lx = gx + gw + 0.25, lwid = AX + AW - lx;
  box(s, lx, AY, lwid, AH, { fill: C.accent2, lineColor: HEX.accent2, name: "Moves card" });
  txt(s, "The moves we need", { x: lx + 0.15, y: AY + 0.15, w: lwid - 0.3, h: 0.35, fontSize: 15, bold: true, color: C.text2 });
  const moves = [["IT operations", "watching → owning the model service"], ["QA and testers", "affected → owning the test gate"], ["Platform operator", "one person → two"]];
  moves.forEach(([a, b], i) => {
    txt(s, [{ text: a, options: { bold: true, breakLine: true } }, { text: b }], { x: lx + 0.15, y: AY + 0.65 + i * 1.08, w: lwid - 0.3, h: 1.0, fontSize: 13 });
  });
}

pres.addSection({ title: S3 });

// ---------- 9. Use Case Card ----------
{
  const s = canvasSlide({ section: S3, n: 5, stage: "What?", name: "Use Case Card", q: "who starts it, what happens, and what comes out?",
    what: "One job the system does, told as actor, trigger, steps and outcome.",
    helps: ["Names the actor and the trigger", "Says what must be true before it starts", "Ends in an outcome you can check"],
    short: "the senior spends minutes reading instead of hours writing.",
    notes: "The use case is 'one small change'. Simple tickets skip most of the seven steps; only real multi-file work runs them all." });
  const c1 = 2.45, c2 = 3.55, c3 = AW - c1 - c2 - 0.7;
  box(s, AX, AY, c1, 1.95, { name: "Actor card" });
  person(s, AX + 0.15, AY + 0.4, 0.75);
  txt(s, "ACTOR AND TRIGGER", { x: AX + 0.11, y: AY + 0.07, w: c1 - 0.2, h: 0.26, fontSize: 11, bold: true, color: C.accent1 });
  txt(s, [{ text: "Delivery engineer", options: { bold: true, breakLine: true } }, { text: "files a ticket in the tracker" }], { x: AX + 1.0, y: AY + 0.4, w: c1 - 1.1, h: 0.8, fontSize: 12.5, valign: "middle" });
  pill(s, AX + 0.15, AY + 1.4, c1 - 0.3, 0.36, "Runs several times a week", C.accent3, C.text2);
  cell(s, AX, AY + 2.05, c1, AH - 2.05, "MUST ALREADY BE TRUE", [
    { text: "The ticket names a real project", options: { bullet: { indent: 12 }, breakLine: true } },
    { text: "The models are loaded and warm", options: { bullet: { indent: 12 }, breakLine: true } },
    { text: "The repo builds before we start", options: { bullet: { indent: 12 } } }], { fs: 12.5 });
  arrow(s, AX + c1 + 0.03, AY + AH / 2 - 0.15, 0.3, 0.3);
  const fx = AX + c1 + 0.35;
  box(s, fx, AY, c2, AH, { name: "Main flow" });
  txt(s, "MAIN FLOW", { x: fx + 0.11, y: AY + 0.07, w: c2 - 0.2, h: 0.26, fontSize: 11, bold: true, color: C.accent1 });
  const flow = ["Someone files a ticket in plain words", "The ticket is rewritten so it is clear", "The work is split; a shared spec is written", "Each part is built in its own copy of the repo", "Tests are written, then run against the build", "A second model reviews the change", "A pull request opens with an honest verdict"];
  flow.forEach((t, i) => {
    const y = AY + 0.4 + i * 0.515;
    num(s, fx + 0.12, y + 0.07, i + 1, 0.34, i === 6 ? C.accent4 : C.accent1);
    txt(s, t, { x: fx + 0.56, y, w: c2 - 0.66, h: 0.48, fontSize: 12.5, valign: "middle" });
  });
  arrow(s, fx + c2 + 0.03, AY + AH / 2 - 0.15, 0.3, 0.3);
  const ox = fx + c2 + 0.35;
  box(s, ox, AY, c3, AH, { fill: TINT.green, lineColor: HEX.accent5, name: "Outcome" });
  txt(s, "OUTCOME", { x: ox + 0.11, y: AY + 0.07, w: c3 - 0.2, h: 0.26, fontSize: 11, bold: true, color: C.accent5 });
  const outs = [["A pull request", "a person reviews"], ["Or a first line", "saying it could not"], ["Either way", "a run history for audit"]];
  outs.forEach(([a, b], i) => txt(s, [{ text: a, options: { bold: true, breakLine: true } }, { text: b }], { x: ox + 0.11, y: AY + 0.5 + i * 1.15, w: c3 - 0.2, h: 1.0, fontSize: 12.5 }));
}

// ---------- 10. Context View ----------
{
  const s = canvasSlide({ section: S3, n: 6, stage: "What?", name: "Context View", q: "what is inside the system, and what does it touch?",
    what: "The system as one box, with everything that goes in and comes out.",
    helps: ["Draws the boundary everyone argues about", "Lists assumptions next to the boxes", "Makes the risks at the edges visible"],
    short: "write the unknowns down, not just the boxes — the edges are where runs fail.",
    notes: "The dashed line is the system boundary. Everything inside runs on hardware we own. The assumptions and warnings below matter as much as the diagram." });
  const iw = 2.3, cwid = 2.6, cx = AX + iw + 0.64, ox = cx + cwid + 0.64, th = 2.3;
  txt(s, "GOES IN", { x: AX, y: AY, w: iw, h: 0.26, fontSize: 11, bold: true, color: C.accent1 });
  txt(s, "COMES OUT", { x: ox, y: AY, w: iw, h: 0.26, fontSize: 11, bold: true, color: C.accent5 });
  const ins = ["Tickets from the tracker", "The repo and its history", "Past runs and lessons"], outs = ["A pull request", "A run history for audit", "New lessons stored"];
  ins.forEach((t, i) => cell(s, AX, AY + 0.32 + i * 0.67, iw, 0.57, null, t, { fs: 12.5, fill: TINT.teal }));
  outs.forEach((t, i) => cell(s, ox, AY + 0.32 + i * 0.67, iw, 0.57, null, t, { fs: 12.5, fill: TINT.green, lineColor: HEX.accent5 }));
  arrow(s, AX + iw + 0.12, AY + 1.0, 0.4, 0.4);
  arrow(s, cx + cwid + 0.12, AY + 1.0, 0.4, 0.4, C.accent5);
  box(s, cx - 0.08, AY, cwid + 0.16, th, { fill: C.background2, lineColor: HEX.accent4, lw: 1.75, dash: "dash", r: 0.12, name: "System boundary" });
  s.addShape(SH.ROUNDED_RECTANGLE, { x: cx + 0.08, y: AY + 0.38, w: cwid - 0.16, h: th - 0.54, fill: { color: C.text2 }, rectRadius: 0.1, objectName: "AIForge" });
  txt(s, "our own hardware", { x: cx, y: AY + 0.07, w: cwid, h: 0.26, fontSize: 11, italic: true, color: C.accent4, align: "center" });
  txt(s, [{ text: "AIForge", options: { fontSize: 20, bold: true, color: C.accent2, breakLine: true } }, { text: "Plans the work", options: { breakLine: true } }, { text: "Writes and tests code", options: { breakLine: true } }, { text: "Reviews and merges" }],
    { x: cx + 0.2, y: AY + 0.42, w: cwid - 0.4, h: th - 0.62, fontSize: 13, color: C.background1, align: "center", valign: "middle" });
  const by = AY + th + 0.15, bh = AH - th - 0.15, bw = (AW - 0.12) / 2;
  const bl = (a) => a.map((v, j) => ({ text: v, options: { bullet: { indent: 12 }, breakLine: j < a.length - 1 } }));
  cell(s, AX, by, bw, bh, "WHAT WE ASSUME", bl(["Models are loaded the right way", "Models stay warm, or runs stop mid-way", "The ticket names a real project"]), { fs: 12.5 });
  cell(s, AX + bw + 0.12, by, bw, bh, "WHAT TO BEWARE OF", bl(["About 3–5 files is today's ceiling", "Some languages still beat the smaller models", "Shared GPUs limit how many tickets run at once"]), { fs: 12.5, fill: TINT.orange, tcol: C.accent4 });
}

// ---------- 11. Service Blueprint ----------
{
  const s = canvasSlide({ section: S3, n: 7, stage: "What?", name: "Service Blueprint", q: "what does the person see, and what runs behind it?",
    what: "The service drawn in lanes: what the person sees on top, the machinery below.",
    helps: ["The line of visibility is the point", "Shows who does what at each stage", "Finds work nobody owns"],
    short: "above the line there are two moments: file it, read it. The design work is all below.",
    notes: "Everything below the dashed line runs without anyone watching. In a live demo, the progress panel shows the 'back stage' row as it happens." });
  const lw = 1.55, cw = (AW - lw) / 4, x0 = AX + lw, rh = 0.6, pitch = 0.65;
  ["Ask", "Work", "Check", "Hand back"].forEach((c, i) => {
    s.addShape(SH.ROUNDED_RECTANGLE, { x: x0 + i * cw, y: AY, w: cw - 0.07, h: 0.4, fill: { color: C.text2 }, rectRadius: 0.06, objectName: "Stage" });
    txt(s, `${i + 1}. ${c}`, { x: x0 + i * cw, y: AY, w: cw - 0.07, h: 0.4, fontSize: 13, bold: true, color: C.background1, align: "center", valign: "middle" });
  });
  const rows = [
    ["The person sees", ["the ticket they wrote", "a run in progress", "test output", "a pull request and a verdict"], C.background1, C.accent1],
    ["The person does", ["files it, in plain words", "nothing — goes elsewhere", "nothing", "reads, comments, merges"], C.background1, C.accent1],
    ["Front stage", ["ticket is picked up", "branch and worktree open", "compile gate runs", "pull request opens"], TINT.teal, C.accent1],
    ["Back stage: agents", ["enhance and clarify", "plan, spec, write", "test, review, reconcile", "write the verdict"], C.accent3, C.text2],
    ["Platform", ["ticket store and routing", "model service on our GPUs", "build tools, test runners", "run history, lessons kept"], C.accent3, C.text2],
  ];
  rows.forEach(([label, vals, fill, col], r) => {
    const y = AY + 0.47 + r * pitch + (r > 2 ? 0.3 : 0);
    txt(s, label, { x: AX, y, w: lw - 0.1, h: rh, fontSize: 12.5, bold: true, color: col, valign: "middle" });
    vals.forEach((v, i) => cell(s, x0 + i * cw, y, cw - 0.07, rh, null, v, { fill, align: "center", fs: 12 }));
  });
  const ly = AY + 0.47 + 3 * pitch - 0.01;
  seg(s, AX, ly, AX + AW, ly, HEX.accent4, 2, { dashType: "dash" });
  txt(s, "line of visibility — below this, nobody is watching", { x: AX, y: ly + 0.04, w: AW, h: 0.22, fontSize: 11, italic: true, color: C.accent4, align: "right" });
}

// ---------- 12. Business Capability Map ----------
{
  const s = canvasSlide({ section: S3, n: 8, stage: "What?", name: "Business Capability Map", q: "what must the business be good at — and who does it today?",
    what: "A grid of everything the business must be able to do. What, never how.",
    helps: ["One view of the whole job, end to end", "Colour shows where help already lands", "The uncoloured boxes are the plan"],
    short: "11 of 18 done by AIForge today, 3 partly. The rest is an ownership gap.",
    notes: "Blue = AIForge does this today. Yellow = partly, being built. White = still all people. The white boxes are mostly about ownership: prioritising, merging, measuring." });
  const cw = AW / 6;
  const D = "d", P = "p", H = "h";
  const cols = [
    ["Understand demand", [["Capture a ticket", H], ["Clarify what is wanted", D], ["Prioritise", H]]],
    ["Design the change", [["Read the codebase", D], ["Split the work", D], ["Agree the contract", D]]],
    ["Build the change", [["Write the code", D], ["Wire files together", D], ["Keep to standards", P]]],
    ["Prove quality", [["Write tests", D], ["Run the build", D], ["Second-pair review", D]]],
    ["Release and operate", [["Open a pull request", D], ["Merge", H], ["Run the platform", P]]],
    ["Learn and improve", [["Keep lessons", D], ["Share across the team", P], ["Measure adoption", H]]],
  ];
  const fill = { d: C.accent3, p: C.accent2, h: C.background1 };
  cols.forEach(([head, items], i) => {
    const x = AX + i * cw;
    s.addShape(SH.ROUNDED_RECTANGLE, { x, y: AY, w: cw - 0.07, h: 0.68, fill: { color: C.text2 }, rectRadius: 0.06, objectName: "Capability group" });
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
  const s = canvasSlide({ section: S3, n: 9, stage: "What?", name: "Capability Card", q: "what does one capability need — people, process, technology?",
    what: "One capability taken apart: who supports it, how it runs, how mature it is.",
    helps: ["People, process, technology — in that order", "A maturity level you can argue about", "The gap to target becomes the to-do list"],
    short: "raise it with bigger local models, shared memory, and a named owner for the platform.",
    notes: "This card is for the capability 'Build the change'. Maturity today is Good. The weakest link overall is memory: it works, but sharing it across the team is only now being built." });
  box(s, AX, AY, AW, 0.78, { name: "Capability header" });
  txt(s, [{ text: "BUILD THE CHANGE", options: { fontSize: 11, bold: true, color: C.accent1, breakLine: true } }, { text: "Turn an agreed spec into code that compiles and fits the repo it lands in." }],
    { x: AX + 0.15, y: AY, w: 5.0, h: 0.78, fontSize: 13, valign: "middle" });
  txt(s, "MATURITY", { x: AX + 5.3, y: AY + 0.06, w: 3.0, h: 0.22, fontSize: 10, bold: true, color: C.accent6, align: "center" });
  ["Growing", "Good", "Strong"].forEach((t, i) => {
    const on = i === 1;
    s.addShape(SH.ROUNDED_RECTANGLE, { x: AX + 5.3 + i * 1.02, y: AY + 0.31, w: 0.97, h: 0.36, fill: { color: on ? C.accent5 : C.background2 }, rectRadius: 0.06, line: { color: HEX.accent3, width: 1 }, objectName: "Maturity step" });
    txt(s, t, { x: AX + 5.3 + i * 1.02, y: AY + 0.31, w: 0.97, h: 0.36, fontSize: 12, bold: on, color: on ? C.background1 : C.accent6, align: "center", valign: "middle" });
  });
  const cw = (AW - 0.24) / 3, cy = AY + 0.9, ch = 2.15;
  const cols = [
    ["People", ["One platform operator today", "Delivery engineer reviews the output", "Nobody named for the model service"], C.accent1],
    ["Process", ["Spec and contract written before code", "Each part built in its own worktree", "Only compiling code reaches a merge"], C.text2],
    ["Technology", ["Local models on hardware we own", "Repo map and past-run memory", "Build and test tools already in use"], C.accent5],
  ];
  cols.forEach(([h, items, col], i) => {
    const x = AX + i * (cw + 0.12);
    box(s, x, cy, cw, ch, { name: "Capability column" });
    num(s, x + 0.12, cy + 0.12, i + 1, 0.4, col);
    txt(s, h, { x: x + 0.62, y: cy + 0.12, w: cw - 0.75, h: 0.4, fontSize: 15, bold: true, color: C.text2, valign: "middle" });
    txt(s, items.map((v, j) => ({ text: v, options: { bullet: { indent: 12 }, breakLine: j < items.length - 1 } })), { x: x + 0.14, y: cy + 0.62, w: cw - 0.28, h: ch - 0.7, fontSize: 12.5, paraSpaceAfter: 2 });
  });
  const gy = cy + ch + 0.12, gh = AH - (gy - AY);
  box(s, AX, gy, AW, gh, { fill: TINT.orange, lineColor: HEX.accent4, name: "Gap to target" });
  txt(s, "GAP TO TARGET", { x: AX + 0.15, y: gy + 0.07, w: 3, h: 0.26, fontSize: 11, bold: true, color: C.accent4 });
  ["Ceiling is 3–5 files; target is 8–10", "Memory not yet shared across the team", "Second operator not trained"].forEach((t, i) => {
    txt(s, t, { x: AX + 0.15 + i * (AW - 0.3) / 3, y: gy + 0.34, w: (AW - 0.3) / 3 - 0.15, h: gh - 0.38, fontSize: 12.5, bold: true, color: C.text1 });
  });
}

pres.addSection({ title: S4 });

// ---------- 14. ASR Card ----------
{
  const s = canvasSlide({ section: S4, n: 10, stage: "How?", name: "ASR Card", q: "which few requirements shape the whole design?",
    what: "ASR = architecturally significant requirement: a rule the design cannot break.",
    helps: ["Picks the few rules that really matter", "States the risk next to the rule", "Each one later needs a decision and a measure"],
    short: "three rules shaped every design choice. Break any one and the tool is not worth using.",
    notes: "Each card states the requirement, how critical it is, what it risks or costs, and the proof that it holds. These three cards drive the decision record and the QATT card that follow." });
  const cw = (AW - 0.24) / 3;
  const asr = [
    ["Do the job on its own", "Ticket in, pull request out. Nobody in the middle.", "RISK", "Bad automatic pull requests destroy trust fast.", "The first full run went from ticket to pull request with no help.", "HIGH"],
    ["Make the files fit together", "Change five files and they still build as one piece.", "RISK", "Without it, big tickets look done and do not compile.", "0 working linked lines → 53, once a shared spec was added.", "HIGH"],
    ["Stay on our machines", "Hardware we own. No cloud. Works with the internet off.", "COST", "Local models are weaker than hosted ones.", "Zero runs have sent data outside our network.", "MEDIUM-HIGH"],
  ];
  asr.forEach(([h, b, rl, rk, p, lvl], i) => {
    const x = AX + i * (cw + 0.12), hi = lvl === "HIGH";
    box(s, x, AY, cw, AH, { name: "ASR card" });
    num(s, x + 0.15, AY + 0.15, i + 1, 0.45);
    pill(s, x + cw - 1.45, AY + 0.2, 1.3, 0.34, lvl, hi ? C.accent4 : C.accent2, hi ? C.background1 : C.text1);
    txt(s, h, { x: x + 0.15, y: AY + 0.7, w: cw - 0.3, h: 0.62, fontSize: 16, bold: true, color: C.text2, valign: "middle" });
    txt(s, b, { x: x + 0.15, y: AY + 1.36, w: cw - 0.3, h: 0.66, fontSize: 12.5 });
    txt(s, [{ text: rl + "  ", options: { bold: true, color: C.accent4, fontSize: 11 } }, { text: rk }], { x: x + 0.15, y: AY + 2.06, w: cw - 0.3, h: 0.68, fontSize: 12.5 });
    box(s, x + 0.12, AY + 2.86, cw - 0.24, AH - 2.98, { fill: TINT.green, lineColor: TINT.green, name: "Proof" });
    txt(s, [{ text: "PROOF", options: { bold: true, color: C.accent5, fontSize: 11, breakLine: true } }, { text: p }], { x: x + 0.22, y: AY + 2.91, w: cw - 0.44, h: AH - 3.08, fontSize: 12.5, valign: "middle" });
  });
}

// ---------- 15. QATT Card ----------
{
  const s = canvasSlide({ section: S4, n: 11, stage: "How?", name: "QATT Card", q: "how do we turn “it must be good” into a number?",
    what: "A quality written as a test scenario: who does what, and the measured response.",
    helps: ["Turns a wish into a pass or fail", "Six fixed parts, so nothing is vague", "Gives every ASR a way to be checked"],
    short: "splitting the work beat waiting for a bigger model — and we have the number to show it.",
    notes: "QATT = quality attribute scenario. The top chain is one scenario written out in the six standard parts. The three cards below are further scenarios in short form. Said out loud: hard compile-and-fix work still needs a human finish." });
  txt(s, [{ text: "SCENARIO   ", options: { bold: true, color: C.accent1, fontSize: 11 } }, { text: "A multi-file ticket comes out as one working change", options: { bold: true, color: C.text2 } }], { x: AX, y: AY, w: AW, h: 0.36, fontSize: 14, valign: "middle" });
  const parts = [["SOURCE", "A delivery engineer"], ["STIMULUS", "files a ticket that touches five files"], ["ENVIRONMENT", "a normal run, local models, no cloud"], ["ARTIFACT", "the AIForge agent line"], ["RESPONSE", "one merged change that builds; the parts link"], ["MEASURE", "0 → 53 linked lines; first full run green"]];
  const pw = AW / 6;
  parts.forEach(([t, b], i) => {
    const last = i === 5;
    s.addShape(i === 0 ? SH.PENTAGON : SH.CHEVRON, { x: AX + i * pw, y: AY + 0.42, w: pw + (last ? 0 : 0.12), h: 0.38, fill: { color: last ? C.accent4 : (i % 2 ? C.accent1 : C.text2) }, objectName: "Scenario part" });
    txt(s, t, { x: AX + i * pw + 0.16, y: AY + 0.42, w: pw - 0.2, h: 0.38, fontSize: 10, bold: true, color: C.background1, align: "center", valign: "middle" });
    cell(s, AX + i * pw + 0.02, AY + 0.86, pw - 0.07, 1.02, null, b, { fs: 12, align: "center", fill: last ? C.accent2 : C.background1, lineColor: last ? HEX.accent4 : HEX.accent3, bold: last });
  });
  txt(s, "MORE SCENARIOS", { x: AX, y: AY + 2.02, w: AW, h: 0.26, fontSize: 11, bold: true, color: C.accent1 });
  const more = [
    ["Nothing leaves our network", "A check fails the build if it would call out", "Running today, small batch", C.accent5],
    ["We know the size limit", "Files per ticket handled cleanly", "3–5 files now", C.accent4],
    ["Team memory does not bloat", "Duplicate notes; growth per week", "Fold step designed", C.accent6],
  ];
  const cw = (AW - 0.24) / 3, my = AY + 2.32, mh = AH - 2.32;
  more.forEach(([h, chk, st, col], i) => {
    const x = AX + i * (cw + 0.12);
    box(s, x, my, cw, mh, { name: "Scenario card" });
    txt(s, h, { x: x + 0.14, y: my + 0.08, w: cw - 0.28, h: 0.5, fontSize: 13, bold: true, color: C.text2, valign: "middle" });
    txt(s, [{ text: "Check:  ", options: { bold: true, color: C.accent1 } }, { text: chk }], { x: x + 0.14, y: my + 0.64, w: cw - 0.28, h: 0.56, fontSize: 12.5 });
    pill(s, x + 0.14, my + mh - 0.44, cw - 0.28, 0.34, st, col, C.background1);
  });
}

// ---------- 16. Decision Record (ADR) ----------
{
  const s = canvasSlide({ section: S4, n: 12, stage: "How?", name: "Decision Record (ADR)", q: "what did we decide, what else did we consider, and why?",
    what: "ADR = architecture decision record. One decision with its options, reasons and cost.",
    helps: ["Keeps the reasons, so nobody re-argues them", "Forces real options, not one favourite", "Names the bias you checked and the owner"],
    short: "we did not pick it because we liked it — it is the one our tests kept passing.",
    notes: "Myth we tested: 'just wait for a bigger model'. Same models, same machines — only splitting the work differently fixed it. The decisions log has four settled decisions and three still open, all about team memory." });
  cell(s, AX, AY, AW, 0.86, "CONTEXT", "Our local models hold about 3–5 files at once. A multi-file ticket must still build as one piece — and no code may leave.", { fs: 12.5 });
  const ow = (AW - 0.36) / 4, oy = AY + 0.94, oh = 1.38;
  const opts = [["Ready-made agent", "Broke on our model server; cannot build Java.", false], ["One big model", "0 linked lines on a multi-file ticket.", false], ["Cloud AI", "Works — and sends our code outside. Not allowed.", false], ["Small-agent line", "0 → 53 linked lines. Builds before every merge.", true]];
  opts.forEach(([h, b, pick], i) => {
    const x = AX + i * (ow + 0.12);
    box(s, x, oy, ow, oh, { fill: pick ? C.accent1 : C.background1, lineColor: pick ? HEX.accent1 : HEX.accent3, name: "Option" });
    pill(s, x + 0.12, oy + 0.1, 1.05, 0.28, pick ? "CHOSEN" : "REJECTED", pick ? C.accent2 : TINT.orange, pick ? C.text1 : C.accent4);
    txt(s, h, { x: x + 0.12, y: oy + 0.42, w: ow - 0.24, h: 0.3, fontSize: 13.5, bold: true, color: pick ? C.background1 : C.text2 });
    txt(s, b, { x: x + 0.12, y: oy + 0.74, w: ow - 0.24, h: 0.6, fontSize: 12, color: pick ? C.background1 : C.text1 });
  });
  const dy = oy + oh + 0.08, dh = AH - (dy - AY), w1 = 3.05, w2 = 3.05, w3 = AW - w1 - w2 - 0.24;
  cell(s, AX, dy, w1, dh, "DECISION — WE WILL…", "finish each ticket with a line of small specialist agents, each with one small job. Simple tickets skip the line.", { fill: C.accent2, lineColor: HEX.accent4, lw: 1.5, tcol: C.text2, fs: 12.5, bold: true });
  cell(s, AX + w1 + 0.12, dy, w2, dh, "CONSEQUENCES", [
    { text: "+ ", options: { bold: true, color: C.accent5 } }, { text: "each role is checked on its own; a bad part fails alone", options: { breakLine: true } },
    { text: "– ", options: { bold: true, color: C.accent4 } }, { text: "more model calls, more waiting, more moving parts" }], { fs: 12.5 });
  const rx = AX + w1 + w2 + 0.24;
  box(s, rx, dy, w3, dh, { name: "Characteristics" });
  txt(s, "REVERSIBILITY", { x: rx + 0.11, y: dy + 0.07, w: w3 - 0.22, h: 0.26, fontSize: 11, bold: true, color: C.accent1 });
  seg(s, rx + 0.2, dy + 0.52, rx + w3 - 0.2, dy + 0.52, HEX.accent3, 4);
  s.addShape(SH.OVAL, { x: rx + 0.42, y: dy + 0.41, w: 0.22, h: 0.22, fill: { color: C.accent5 }, objectName: "Reversibility marker" });
  txt(s, "easy to undo", { x: rx + 0.11, y: dy + 0.66, w: w3 / 2, h: 0.22, fontSize: 10, color: C.accent6 });
  txt(s, "permanent", { x: rx + w3 / 2, y: dy + 0.66, w: w3 / 2 - 0.11, h: 0.22, fontSize: 10, color: C.accent6, align: "right" });
  txt(s, [{ text: "Bias checked: ", options: { bold: true } }, { text: "“more agents must be better”", options: { breakLine: true } }, { text: "Owner: ", options: { bold: true } }, { text: "project lead" }], { x: rx + 0.11, y: dy + 0.94, w: w3 - 0.22, h: dh - 1.0, fontSize: 12 });
}

pres.addSection({ title: S5 });

// ---------- 17. OKR Card ----------
{
  const s = canvasSlide({ section: S5, n: 13, stage: "Where next?", name: "OKR Card", q: "what does good look like, in numbers we can check?",
    what: "OKR = objective and key results: one goal and a few measures.",
    helps: ["One goal everyone can repeat", "Measures you can actually check", "Shows honestly where you are today"],
    short: "the tool works; now we must measure how often it succeeds. The first row is the problem.",
    notes: "Without the first number there is no case to make this standard practice. Bars show how far today is from target; the dashed bar means we do not measure it yet." });
  s.addShape(SH.ROUNDED_RECTANGLE, { x: AX, y: AY, w: AW, h: 0.68, fill: { color: C.text2 }, rectRadius: 0.08, objectName: "Objective" });
  txt(s, [{ text: "OBJECTIVE   ", options: { bold: true, color: C.accent2, fontSize: 11 } }, { text: "Make AIForge the normal way small work gets done", options: { bold: true, color: C.background1 } }], { x: AX + 0.2, y: AY, w: AW - 0.4, h: 0.68, fontSize: 16, valign: "middle" });
  const kx = AX, kw = 3.45, bx = AX + 3.6, bw = 2.5, tx = bx + bw + 0.15, tw = 1.15, gx2 = tx + tw + 0.05, gw = AX + AW - gx2;
  const hy = AY + 0.76;
  [["KEY RESULT", kx, kw, "left"], ["PROGRESS TO TARGET", bx, bw, "left"], ["TODAY", tx, tw, "center"], ["TARGET", gx2, gw, "center"]].forEach(([t, x, w, a]) => txt(s, t, { x, y: hy, w, h: 0.24, fontSize: 10, bold: true, color: C.accent6, align: a }));
  const krs = [
    ["Tickets that end in a merged pull request", null, "Not measured", "3 in 4", C.accent4],
    ["Files one ticket can change cleanly", 0.45, "3 to 5", "8 to 10", C.accent4],
    ["Tickets filed by people other than the leads", 0.06, "Almost none", "Half", C.accent4],
    ["People who can run and fix the platform", 0.5, "1", "2", C.accent4],
    ["Runs where data left our network", 1, "Zero", "Zero", C.accent5],
  ];
  const ry = hy + 0.28, pitch = (AY + AH - ry) / 5;
  krs.forEach(([t, pct, now, tgt, col], i) => {
    const y = ry + i * pitch, h = pitch - 0.07;
    box(s, kx, y, AW, h, { name: "Key result row" });
    txt(s, t, { x: kx + 0.14, y, w: kw - 0.2, h, fontSize: 12.5, valign: "middle" });
    const by = y + h / 2 - 0.11;
    s.addShape(SH.ROUNDED_RECTANGLE, { x: bx, y: by, w: bw, h: 0.22, fill: { color: C.background2 }, rectRadius: 0.11, line: { color: HEX.accent6, width: 1, dashType: pct === null ? "dash" : "solid" }, objectName: "Progress track" });
    if (pct) s.addShape(SH.ROUNDED_RECTANGLE, { x: bx, y: by, w: Math.max(bw * pct, 0.22), h: 0.22, fill: { color: col }, rectRadius: 0.11, objectName: "Progress" });
    txt(s, now, { x: tx, y, w: tw, h, fontSize: 12.5, bold: true, color: col, align: "center", valign: "middle" });
    txt(s, tgt, { x: gx2, y, w: gw - 0.1, h, fontSize: 12.5, bold: true, color: C.text2, align: "center", valign: "middle" });
  });
}

// ---------- 18. Roadmap Canvas ----------
{
  const s = canvasSlide({ section: S5, n: 14, stage: "Where next?", name: "Roadmap Canvas", q: "what happens when — for product, platform and people?",
    what: "The plan over time, with product, platform and people in one view.",
    helps: ["Change is people and process, not only code", "Each row moves together, quarter by quarter", "Every item traces back to an OKR or a gap"],
    short: "one rule for the whole year: nothing on this roadmap moves work off our own hardware.",
    notes: "Read each row left to right. The people row is the one most likely to slip, and it is the one the power/interest grid said matters most." });
  const lw = 1.3, cw = (AW - lw) / 4, x0 = AX + lw;
  ["Q1", "Q2", "Q3", "Q4"].forEach((q, i) => {
    s.addShape(i === 0 ? SH.PENTAGON : SH.CHEVRON, { x: x0 + i * cw, y: AY, w: cw + (i < 3 ? 0.1 : -0.03), h: 0.5, fill: { color: i % 2 ? C.accent1 : C.text2 }, objectName: "Quarter" });
    txt(s, q, { x: x0 + i * cw, y: AY, w: cw, h: 0.5, fontSize: 15, bold: true, color: C.background1, align: "center", valign: "middle" });
  });
  const rows = [
    ["Product", ["Honest verdict on every pull request", "Team memory sharing live", "Bigger tickets, more files", "Open to every team"], C.accent1, TINT.teal],
    ["Platform", ["GPU upgrade sized", "Bigger local models tested", "Model service run by IT operations", "Capacity planned ahead"], C.accent4, TINT.orange],
    ["People", ["Second operator named", "QA owns the test gate", "Juniors onboarded", "Adoption measured monthly"], C.accent5, TINT.green],
  ];
  const ry = AY + 0.6, pitch = (AH - 0.6) / 3;
  rows.forEach(([label, vals, col, fill], r) => {
    const y = ry + r * pitch, h = pitch - 0.1;
    s.addShape(SH.ROUNDED_RECTANGLE, { x: AX, y, w: lw - 0.1, h, fill: { color: col }, rectRadius: 0.08, objectName: "Row label" });
    txt(s, label, { x: AX, y, w: lw - 0.1, h, fontSize: 15, bold: true, color: C.background1, align: "center", valign: "middle" });
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
    ["Decision Record", "So we use a line of small agents."],
    ["QATT Card", "Proof: 0 → 53 linked lines."],
    ["OKR Card", "Next: 3 in 4 tickets end in a merge."],
  ];
  const w = 1.72, gap = (12.13 - 6 * w) / 5;
  chain.forEach(([c, t], i) => {
    const x = 0.6 + i * (w + gap), rot = i % 2 ? -1.5 : 1.5;
    pill(s, x, 2.0, w, 0.36, c, i % 2 ? C.accent1 : C.text2, C.background1);
    s.addShape(SH.RECTANGLE, { x, y: 2.6, w, h: 1.85, fill: { color: C.accent2 }, rotate: rot,
      shadow: { type: "outer", color: HEX.accent6, opacity: 0.35, blur: 4, offset: 2, angle: 90 }, objectName: "Sticky note" });
    txt(s, t, { x: x + 0.12, y: 2.6, w: w - 0.24, h: 1.85, fontSize: 14, bold: true, color: C.text1, align: "center", valign: "middle", rotate: rot });
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

// ---------- 20. Take away ----------
{
  const s = pres.addSlide({ masterName: "DARK", sectionTitle: S6 });
  txt(s, "What to take away", { x: 0.8, y: 0.6, w: 11.7, h: 0.9, fontSize: 40, bold: true, color: C.background1, fontFace: THEME.headFontFace });
  txt(s, "How to use the canvases on your own work — and what AIForge taught us.", { x: 0.8, y: 1.45, w: 11.7, h: 0.5, fontSize: 20, color: C.accent3 });
  const cols = [
    ["Using the canvases", ["Start with the person, not the technology", "One page each — if it does not fit, it is not clear yet", "Fill boxes with facts; leave the gaps visible", "Pin them side by side and follow the links"]],
    ["What AIForge taught us", ["The limit was the design, not the model", "The canvases made the argument checkable — one page, not a long thread", "A tool one person can run is not yet a tool the company owns"]],
  ];
  cols.forEach(([h, items], i) => {
    const x = 0.8 + i * 6.0;
    s.addShape(SH.ROUNDED_RECTANGLE, { x, y: 2.3, w: 5.6, h: 3.05, fill: { color: "2A6274" }, rectRadius: 0.1, objectName: "Panel" });
    num(s, x + 0.35, 2.52, i + 1, 0.5, i ? C.accent4 : C.accent1);
    txt(s, h, { x: x + 1.0, y: 2.52, w: 4.3, h: 0.5, fontSize: 22, bold: true, color: C.accent2, valign: "middle" });
    txt(s, items.map((t, j) => ({ text: t, options: { bullet: true, breakLine: j < items.length - 1 } })),
      { x: x + 0.35, y: 3.2, w: 4.95, h: 2.35, fontSize: 16, color: C.background1, paraSpaceAfter: 10 });
  });
  txt(s, "Every claim here has a canvas behind it.", { x: 0.8, y: 5.7, w: 11.7, h: 0.4, fontSize: 15, italic: true, color: C.accent3 });
  s.addNotes("Close by asking the audience to pick one canvas and fill it for their own project this week. The persona card is the easiest place to start.");
}

(async () => {
  const out = process.argv[2] || "IASA-Canvases-with-AIForge.pptx";
  await pres.writeFile({ fileName: out });
  await applyTheme(out, THEME);
  console.log("wrote", out);
})();
