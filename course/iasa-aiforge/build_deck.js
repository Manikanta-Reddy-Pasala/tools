// Simplified, self-explanatory demo deck: AIForge (IASA Masterclass report-out)
const pptxgen = require("pptxgenjs");
const { applyTheme } = require(process.env.SKILL + "/apply_theme.js");

const THEME = {
  name: "AIForge Teal",
  headFontFace: "Cambria",
  bodyFontFace: "Calibri",
  colors: {
    dk1: "1B2A30", lt1: "FFFFFF", dk2: "1F4E5F", lt2: "EEF4F6",
    accent1: "2E7D8C", accent2: "FBE7A1", accent3: "C8DDE3", accent4: "D9822B",
    accent5: "5B8C5A", accent6: "8A9BA1", hlink: "2E7D8C", folHlink: "1F4E5F",
  },
};
const HEX = THEME.colors;

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.33 x 7.5
pres.title = "AIForge - simple demo deck";
pres.author = "Manikanta Reddy Pasala";
pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
const C = pres.SchemeColor;

// ---------- layouts ----------
pres.defineSlideMaster({
  title: "DARK",
  background: { color: C.text2 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.8, y: 2.0, w: 11.7, h: 1.4, fontSize: 54, bold: true, color: C.background1, fontFace: THEME.headFontFace, valign: "bottom", align: "left", margin: 0 }, text: "" } },
    { placeholder: { options: { name: "body", type: "body", x: 0.8, y: 3.55, w: 11.0, h: 1.6, fontSize: 24, color: C.accent3, valign: "top", align: "left", margin: 0 }, text: "" } },
  ],
});
pres.defineSlideMaster({
  title: "CONTENT",
  background: { color: C.background2 },
  margin: [0.5, 0.6, 0.6, 0.6],
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.6, y: 0.4, w: 9.6, h: 0.8, fontSize: 36, bold: true, color: C.text2, fontFace: THEME.headFontFace, valign: "middle", align: "left", margin: 0 }, text: "" } },
    { placeholder: { options: { name: "body", type: "body", x: 0.6, y: 1.2, w: 9.6, h: 0.5, fontSize: 18, color: C.accent6, valign: "top", align: "left", margin: 0 }, text: "" } },
    { text: { text: "AIForge  ·  IASA Masterclass report-out", options: { x: 0.6, y: 7.05, w: 6, h: 0.3, fontSize: 10, color: C.accent6, margin: 0 } } },
  ],
  slideNumber: { x: 12.3, y: 7.05, w: 0.5, h: 0.3, fontSize: 10, color: C.accent6, align: "right" },
});

// ---------- helpers ----------
function content(title, sub) {
  const s = pres.addSlide({ masterName: "CONTENT" });
  s.addText(title, { placeholder: "title" });
  if (sub) s.addText(sub, { placeholder: "body" });
  return s;
}
// small sticky note naming the IASA canvas behind the slide (the original deck's motif)
function canvasTag(s, label) {
  s.addShape(pres.shapes.RECTANGLE, {
    x: 10.55, y: 0.4, w: 2.2, h: 0.85, fill: { color: C.accent2 }, rotate: 2,
    shadow: { type: "outer", color: "8A9BA1", opacity: 0.35, blur: 4, offset: 2, angle: 90 },
    objectName: "Canvas tag",
  });
  s.addText([{ text: "IASA tool", options: { fontSize: 10, color: C.accent6, breakLine: true } },
             { text: label, options: { fontSize: 14, bold: true, color: C.text1 } }],
    { x: 10.6, y: 0.42, w: 2.1, h: 0.8, align: "center", valign: "middle", rotate: 2, margin: 0, isTextBox: true });
}
// the one-line takeaway band at the bottom of every content slide
function inShort(s, text) {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 0.6, y: 6.15, w: 12.13, h: 0.7, fill: { color: C.text2 }, rectRadius: 0.08, objectName: "In short band" });
  s.addText([{ text: "In short:  ", options: { bold: true, color: C.accent2 } }, { text, options: { color: C.background1 } }],
    { x: 0.85, y: 6.15, w: 11.7, h: 0.7, fontSize: 18, valign: "middle", margin: 0, isTextBox: true });
}
function card(s, x, y, w, h, fill) {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, fill: { color: fill || C.background1 }, rectRadius: 0.1,
    line: { color: HEX.accent3, width: 1 }, objectName: "Card" });
}
function num(s, x, y, n, d = 0.6, fill) {
  s.addShape(pres.shapes.OVAL, { x, y, w: d, h: d, fill: { color: fill || C.accent1 }, objectName: "Number circle" });
  s.addText(String(n), { x, y, w: d, h: d, align: "center", valign: "middle", fontSize: d > 0.55 ? 20 : 14, bold: true, color: C.background1, margin: 0, isTextBox: true });
}
function arrow(s, x, y, w = 0.45, h = 0.45) {
  s.addShape(pres.shapes.RIGHT_ARROW, { x, y, w, h, fill: { color: C.accent1 }, objectName: "Arrow" });
}
function txt(s, text, o) { s.addText(text, Object.assign({ isTextBox: true, margin: 0, valign: "top", color: C.text1, fontSize: 16 }, o)); }

// ========== 1. Title ==========
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("IASA Masterclass  ·  Report out", { x: 0.8, y: 0.7, w: 8, h: 0.4, fontSize: 16, color: C.accent2, margin: 0, isTextBox: true, bold: true });
  s.addText("AIForge — our own AI developer", { placeholder: "title" });
  s.addText([
    { text: "You give it a ticket. It gives back a tested pull request.", options: { breakLine: true } },
    { text: "It runs on machines we own. Nothing leaves the building.", options: {} },
  ], { placeholder: "body" });
  s.addText("Roles only — no names, no customer detail.", { x: 0.8, y: 6.6, w: 8, h: 0.35, fontSize: 12, italic: true, color: C.accent6, margin: 0, isTextBox: true });
  s.addNotes("One sentence to open with: AIForge is a team of AI agents that turns a ticket into a pull request, on our own hardware. Everything after this slide explains that sentence.");
}

// ========== 2. The problem ==========
{
  const s = content("The problem we had", "Three facts about where we work (defence sector, government customer)");
  canvasTag(s, "Business Model Canvas");
  const items = [
    ["Too many small tickets", "Our best engineers spend the day on small, routine changes. The hard work waits."],
    ["Same team, more output", "The plan keeps growing. We have to deliver more without growing the team."],
    ["Cloud AI is not allowed", "No code or data may go to an outside service. Ever. So the usual AI tools are out."],
  ];
  items.forEach(([h, b], i) => {
    const x = 0.6 + i * 4.13;
    card(s, x, 2.0, 3.83, 3.75);
    num(s, x + 0.35, 2.35, i + 1);
    txt(s, h, { x: x + 0.35, y: 3.15, w: 3.2, h: 0.9, fontSize: 22, bold: true, color: C.text2 });
    txt(s, b, { x: x + 0.35, y: 4.1, w: 3.2, h: 1.5, fontSize: 16 });
  });
  inShort(s, "we needed AI help that runs inside our own walls — so we built it.");
  s.addNotes("Keep it to these three facts. The third one is why we could not just buy a tool.");
}

// ========== 3. What AIForge is ==========
{
  const s = content("What AIForge is", "One input, one output — and nobody has to watch in between");
  const boxes = [
    ["A ticket", "Written in plain words, like you would ask a colleague", C.background1, C.text2],
    ["AIForge", "A small team of AI agents on our own GPUs plans, writes, tests and reviews the change", C.accent1, C.background1],
    ["A pull request", "A tested, reviewed code change, ready for a person to read and merge", C.background1, C.text2],
  ];
  boxes.forEach(([h, b, fill, col], i) => {
    const x = 0.6 + i * 4.2;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 1.95, w: 3.6, h: 2.2, fill: { color: fill }, rectRadius: 0.1, line: { color: HEX.accent3, width: 1 }, objectName: "Flow box" });
    txt(s, h, { x: x + 0.3, y: 2.15, w: 3.0, h: 0.6, fontSize: 26, bold: true, color: col });
    txt(s, b, { x: x + 0.3, y: 2.8, w: 3.0, h: 1.3, fontSize: 16, color: col });
    if (i < 2) arrow(s, x + 3.66, 2.83);
  });
  // two ways in + words used
  card(s, 0.6, 4.4, 6.0, 1.55);
  txt(s, "Two ways to use it", { x: 0.85, y: 4.55, w: 5.5, h: 0.4, fontSize: 18, bold: true, color: C.text2 });
  txt(s, [
    { text: "Chat — ", options: { bold: true } }, { text: "talk to it; it reads the code, runs commands, edits files.", options: { breakLine: true } },
    { text: "Ticket — ", options: { bold: true } }, { text: "file it and walk away; a pull request appears.", options: {} },
  ], { x: 0.85, y: 5.0, w: 5.6, h: 0.9, fontSize: 15 });
  card(s, 6.85, 4.4, 5.88, 1.55, C.accent2);
  txt(s, "Words used in this deck", { x: 7.1, y: 4.55, w: 5.4, h: 0.4, fontSize: 18, bold: true, color: C.text2 });
  txt(s, [
    { text: "Pull request (PR) — ", options: { bold: true } }, { text: "a proposed code change a person reviews.", options: { breakLine: true } },
    { text: "Agent — ", options: { bold: true } }, { text: "an AI worker with one small job.", options: {} },
  ], { x: 7.1, y: 5.0, w: 5.45, h: 0.9, fontSize: 15 });
  inShort(s, "a person only touches two moments — writing the ticket and reading the pull request.");
  s.addNotes("If the audience is non-technical, spend a moment on the glossary box. Everything else in the deck builds on ticket -> AIForge -> pull request.");
}

// ========== 4. Who it is for ==========
{
  const s = content("Who it is for", "Three people, described by role");
  canvasTag(s, "Persona Card");
  const ps = [
    ["Delivery engineer", "Main user", "“I know how to do this. I do not have the hours.”", "Small tickets are off their desk; a PR is waiting to read."],
    ["Junior developer", "Learner", "“I want to learn, not sit blocked.”", "The PR shows them the right pattern in our own code."],
    ["Engineering lead", "Decision maker", "“Show me it works before I plan around it.”", "One honest number lands each month."],
  ];
  ps.forEach(([role, tag, quote, win], i) => {
    const x = 0.6 + i * 4.13;
    card(s, x, 1.95, 3.83, 3.9, i === 0 ? C.background1 : C.background1);
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: x + 0.3, y: 2.25, w: 1.6, h: 0.38, fill: { color: i === 0 ? C.accent1 : C.accent3 }, rectRadius: 0.08, objectName: "Role tag" });
    txt(s, tag, { x: x + 0.3, y: 2.25, w: 1.6, h: 0.38, fontSize: 12, bold: true, align: "center", valign: "middle", color: i === 0 ? C.background1 : C.text2 });
    txt(s, role, { x: x + 0.3, y: 2.8, w: 3.3, h: 0.5, fontSize: 22, bold: true, color: C.text2 });
    txt(s, quote, { x: x + 0.3, y: 3.4, w: 3.3, h: 1.1, fontSize: 17, italic: true, color: C.accent1 });
    txt(s, [{ text: "Happy when: ", options: { bold: true } }, { text: win }], { x: x + 0.3, y: 4.6, w: 3.3, h: 1.1, fontSize: 15 });
  });
  inShort(s, "it is built for the delivery engineer. If their day does not change, nothing else matters.");
  s.addNotes("Honest adoption test: do people file a ticket, or still walk over to a senior? Today it is mostly the second.");
}

// ========== 5. Before and after ==========
{
  const s = content("Before and after", "The same small ticket, today and with AIForge");
  canvasTag(s, "Customer Journey");
  const steps = ["Ticket raised", "Picked up", "Code written", "Tested and reviewed", "Merged"];
  const today = ["sits in the backlog", "waits for a senior", "squeezed between other work", "rushed at the end", "days later"];
  const after = ["picked up as written", "starts at once", "agents write it in a copy of the code", "tests first, second AI reviews", "PR ready to read"];
  const x0 = 2.6, cw = 2.0;
  steps.forEach((st, i) => {
    const x = x0 + i * cw;
    s.addShape(pres.shapes.CHEVRON, { x, y: 1.95, w: cw - 0.05, h: 0.7, fill: { color: C.text2 }, objectName: "Step" });
    txt(s, st, { x: x + 0.3, y: 1.95, w: cw - 0.6, h: 0.7, fontSize: 13, bold: true, color: C.background1, align: "center", valign: "middle" });
  });
  const rows = [["Today", today, "F6E3D3", C.accent4], ["With AIForge", after, "DCEEE2", C.accent5]];
  rows.forEach(([label, vals, fill, col], r) => {
    const y = 2.9 + r * 1.55;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 0.6, y, w: 1.85, h: 1.35, fill: { color: col }, rectRadius: 0.1, objectName: "Row label" });
    txt(s, label, { x: 0.6, y, w: 1.85, h: 1.35, fontSize: 18, bold: true, color: C.background1, align: "center", valign: "middle" });
    vals.forEach((v, i) => {
      s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: x0 + i * cw + 0.05, y, w: cw - 0.15, h: 1.35, fill: { color: fill }, rectRadius: 0.08, objectName: "Cell" });
      txt(s, v, { x: x0 + i * cw + 0.15, y, w: cw - 0.35, h: 1.35, fontSize: 15, valign: "middle", align: "center" });
    });
  });
  inShort(s, "the cost was never the typing — it was the waiting. AIForge removes the wait.");
  s.addNotes("Point at the top row first (orange), then the bottom row (green). The person now joins at the pull request, not before it.");
}

// ========== 6. How one ticket flows ==========
{
  const s = content("How one ticket flows", "Seven AI agents, each with one small job, in order");
  const roles = [
    ["Enhancer", "makes the ticket clear"], ["Architect", "splits the work, writes a shared plan"],
    ["Senior dev", "sets the shape of the code"], ["Developer", "writes each part"],
    ["Tester", "writes and runs tests"], ["Reviewer", "a second AI checks the work"], ["Reconcile", "joins it all and builds until it passes"],
  ];
  const w = 1.6, gap = 0.135;
  roles.forEach(([r, d], i) => {
    const x = 0.6 + i * (w + gap);
    num(s, x + w / 2 - 0.3, 1.95, i + 1, 0.6, i === 5 ? C.accent4 : C.accent1);
    card(s, x, 2.7, w, 2.0);
    txt(s, r, { x: x + 0.1, y: 2.85, w: w - 0.2, h: 0.45, fontSize: 16, bold: true, color: C.text2, align: "center" });
    txt(s, d, { x: x + 0.12, y: 3.35, w: w - 0.24, h: 1.25, fontSize: 14, align: "center" });
  });
  card(s, 0.6, 4.95, 12.13, 0.95, C.accent2);
  txt(s, [
    { text: "Why split it up?  ", options: { bold: true, color: C.text2 } },
    { text: "Our local AI models can only hold about 3–5 files at once. Small jobs with only the context they need fit; one big job does not." },
  ], { x: 0.85, y: 4.95, w: 11.7, h: 0.95, fontSize: 16, valign: "middle" });
  inShort(s, "one shared plan first, tests before code, and nothing is merged unless it builds.");
  s.addNotes("Simple tickets skip most of this line; only real multi-file work runs all seven steps. In the demo you will see these step names in the progress panel.");
}

// ========== 7. What you see vs behind ==========
{
  const s = content("What you see vs what runs behind", "Everything below the line runs without anyone watching");
  canvasTag(s, "Service Blueprint");
  const cols = ["1. Ask", "2. Work", "3. Check", "4. Hand back"];
  const see = ["You write the ticket", "A run in progress (you can leave)", "Test results", "A pull request with an honest verdict"];
  const behind = ["Ticket is cleaned up and routed", "Plan, shared spec, code written", "Tests, second-AI review, build", "Verdict written, lessons saved"];
  const x0 = 2.6, cw = 2.53;
  cols.forEach((c, i) => {
    txt(s, c, { x: x0 + i * cw, y: 1.9, w: cw - 0.15, h: 0.45, fontSize: 18, bold: true, color: C.text2, align: "center" });
  });
  txt(s, "You see", { x: 0.6, y: 2.45, w: 1.85, h: 1.2, fontSize: 18, bold: true, color: C.accent1, valign: "middle" });
  txt(s, "Behind the scenes", { x: 0.6, y: 4.35, w: 1.85, h: 1.2, fontSize: 18, bold: true, color: C.accent6, valign: "middle" });
  see.forEach((v, i) => {
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: x0 + i * cw, y: 2.45, w: cw - 0.15, h: 1.2, fill: { color: C.background1 }, line: { color: HEX.accent1, width: 1.5 }, rectRadius: 0.08, objectName: "Seen cell" });
    txt(s, v, { x: x0 + i * cw + 0.12, y: 2.45, w: cw - 0.39, h: 1.2, fontSize: 15, align: "center", valign: "middle" });
  });
  s.addShape(pres.shapes.LINE, { x: 0.6, y: 4.0, w: 12.13, h: 0, line: { color: HEX.accent4, width: 2, dashType: "dash" }, objectName: "Line of visibility" });
  txt(s, "line of visibility", { x: 10.6, y: 3.72, w: 2.1, h: 0.25, fontSize: 11, italic: true, color: C.accent4, align: "right" });
  behind.forEach((v, i) => {
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: x0 + i * cw, y: 4.35, w: cw - 0.15, h: 1.2, fill: { color: C.accent3 }, rectRadius: 0.08, objectName: "Behind cell" });
    txt(s, v, { x: x0 + i * cw + 0.12, y: 4.35, w: cw - 0.39, h: 1.2, fontSize: 15, align: "center", valign: "middle" });
  });
  inShort(s, "for the person it is two moments: file it, then read it. The design work is all below the line.");
  s.addNotes("This is the slide to point back to during the demo: the run panel shows the 'behind the scenes' row live.");
}

// ========== 8. Three things it must get right ==========
{
  const s = content("Three things it must get right", "Break any one and the tool is not worth using");
  canvasTag(s, "ASR Cards");
  const asr = [
    ["Do the job on its own", "Ticket in, pull request out — nobody in the middle.", "Proof: the first full run went from ticket to PR with no help.", "HIGH"],
    ["Make the files fit together", "Change five files and they still work as one: imports connect, calls match, it builds.", "Proof: 0 working linked lines → 53 once we added a shared plan.", "HIGH"],
    ["Stay on our machines", "Runs on hardware we own. No cloud. Works with the internet off.", "Proof: zero runs have sent data outside our network.", "MED-HIGH"],
  ];
  asr.forEach(([h, b, p, lvl], i) => {
    const x = 0.6 + i * 4.13;
    card(s, x, 1.95, 3.83, 3.95);
    num(s, x + 0.3, 2.25, i + 1);
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: x + 2.35, y: 2.35, w: 1.2, h: 0.4, fill: { color: lvl === "HIGH" ? C.accent4 : C.accent2 }, rectRadius: 0.08, objectName: "Priority tag" });
    txt(s, lvl, { x: x + 2.35, y: 2.35, w: 1.2, h: 0.4, fontSize: 12, bold: true, align: "center", valign: "middle", color: lvl === "HIGH" ? C.background1 : C.text1 });
    txt(s, h, { x: x + 0.3, y: 3.0, w: 3.25, h: 0.8, fontSize: 20, bold: true, color: C.text2 });
    txt(s, b, { x: x + 0.3, y: 3.8, w: 3.25, h: 1.05, fontSize: 15 });
    txt(s, p, { x: x + 0.3, y: 4.9, w: 3.25, h: 0.9, fontSize: 14, italic: true, color: C.accent1 });
  });
  inShort(s, "these three rules shaped every design choice.");
  s.addNotes("ASR = architecturally significant requirement: a requirement that shapes the whole design.");
}

// ========== 9. Options ==========
{
  const s = content("Why we built our own", "We compared four ways to get an AI developer");
  canvasTag(s, "ADR");
  const Y = "Yes", N = "No";
  const hdr = ["", "Ready-made agent", "One big model", "Cloud AI", "AIForge"].map((t, i) => ({ text: t, options: { bold: true, color: i === 4 ? "FFFFFF" : HEX.dk2, fill: { color: i === 4 ? HEX.accent1 : HEX.accent3 }, align: "center" } }));
  const rows = [
    ["Code stays inside", Y, Y, N, Y],
    ["Multi-file change still builds", N, N, Y, Y],
    ["Checked by a second AI", N, N, N, Y],
    ["Runs on our own machines", N, Y, N, Y],
  ].map(r => r.map((v, i) => ({ text: v, options: i === 0 ? { bold: true, align: "left", color: HEX.dk1 } : { align: "center", bold: true, color: v === Y ? HEX.accent5 : HEX.accent4, fill: { color: i === 4 ? "E3F1F3" : "FFFFFF" } } })));
  s.addTable([hdr, ...rows], { x: 0.6, y: 1.95, w: 12.13, colW: [3.73, 2.1, 2.1, 2.1, 2.1], rowH: 0.62, fontSize: 17, fontFace: THEME.bodyFontFace, border: { type: "solid", pt: 1, color: HEX.accent3 }, valign: "middle", fill: { color: "FFFFFF" } });
  txt(s, "The cloud AI works best on paper — but it sends our code outside, which is not allowed. The ready-made agent broke on our model server and could not build Java.",
    { x: 0.6, y: 5.3, w: 12.13, h: 0.7, fontSize: 15, color: C.text1 });
  inShort(s, "only AIForge passes every row — and our tests proved it.");
  s.addNotes("Myth we tested: 'just wait for a bigger model'. Same models, same machines - only splitting the work differently fixed it.");
}

// ========== 10. Proof in numbers ==========
{
  const s = content("What the numbers say", "Measured on our own machines, not estimated");
  canvasTag(s, "QATT Card");
  const stats = [
    ["0 → 53", "linked lines of working code in a multi-file ticket, once work was split with a shared plan", C.accent1],
    ["3–5", "files one ticket can change cleanly today. Target: 8–10 after the GPU upgrade", C.accent4],
    ["0", "runs where any data left our network", C.accent5],
  ];
  stats.forEach(([big, lab, col], i) => {
    const x = 0.6 + i * 4.13;
    card(s, x, 1.95, 3.83, 3.95);
    txt(s, big, { x: x + 0.2, y: 2.2, w: 3.43, h: 1.5, fontSize: 66, bold: true, color: col, align: "center", valign: "middle", fontFace: THEME.headFontFace });
    txt(s, lab, { x: x + 0.35, y: 3.85, w: 3.13, h: 1.8, fontSize: 16, align: "center" });
  });
  inShort(s, "splitting the work beat waiting for a bigger model.");
  s.addNotes("Be upfront: hard compile-and-fix work still needs a human finish, and shared GPUs limit how many tickets run at once.");
}

// ========== 11. Where we are ==========
{
  const s = content("Where we are today", "Goal: make AIForge the normal way small work gets done");
  canvasTag(s, "OKR Card");
  const hdr = ["What we measure", "Target", "Today"].map(t => ({ text: t, options: { bold: true, color: "FFFFFF", fill: { color: HEX.dk2 } } }));
  const good = { color: HEX.accent5, bold: true }, gap = { color: HEX.accent4, bold: true };
  const rows = [
    ["Tickets that end in a merged pull request", "3 in 4", "Not measured yet", gap],
    ["Files one ticket can change cleanly", "8 to 10", "3 to 5", gap],
    ["Tickets filed by people other than the leads", "Half", "Almost none", gap],
    ["People who can run and fix the platform", "2", "1", gap],
    ["Runs where data left our network", "Zero", "Zero", good],
  ].map(([a, b, c, st]) => [{ text: a }, { text: b, options: { bold: true } }, { text: c, options: st }]);
  s.addTable([hdr, ...rows], { x: 0.6, y: 1.95, w: 12.13, colW: [6.93, 2.4, 2.8], rowH: 0.62, fontSize: 17, fontFace: THEME.bodyFontFace, color: HEX.dk1, border: { type: "solid", pt: 1, color: HEX.accent3 }, valign: "middle", fill: { color: "FFFFFF" } });
  txt(s, [{ text: "Green", options: { bold: true, color: C.accent5 } }, { text: " = on target.   " }, { text: "Orange", options: { bold: true, color: C.accent4 } }, { text: " = still to close." }],
    { x: 0.6, y: 5.75, w: 8, h: 0.3, fontSize: 13, color: C.accent6 });
  inShort(s, "the tool works; now we must measure how often it succeeds.");
  s.addNotes("OKR = objective and key results: one goal, a few numbers you can actually check.");
}

// ========== 12. Demo ==========
{
  const s = content("Demo: what you will see", "Follow these five steps on screen");
  const steps = [
    ["Write a ticket", "A small change, in plain words — the way you would ask a colleague."],
    ["Start the run", "AIForge picks it up. No setup, nobody needs to watch."],
    ["Watch the agents", "The progress panel shows each step: plan, write, test, review."],
    ["See the checks", "Tests run and a second AI reviews. If it fails, it says so in the first line."],
    ["Read the pull request", "A finished change with an honest verdict, ready to merge."],
  ];
  steps.forEach(([h, b], i) => {
    const y = 1.9 + i * 0.83;
    num(s, 0.6, y + 0.07, i + 1, 0.6, i === 4 ? C.accent4 : C.accent1);
    txt(s, h, { x: 1.45, y, w: 3.4, h: 0.74, fontSize: 20, bold: true, color: C.text2, valign: "middle" });
    txt(s, b, { x: 4.9, y, w: 5.2, h: 0.74, fontSize: 15, valign: "middle" });
  });
  card(s, 10.35, 1.9, 2.38, 4.0, C.accent2);
  txt(s, "Watch for", { x: 10.55, y: 2.05, w: 2.0, h: 0.4, fontSize: 18, bold: true, color: C.text2 });
  txt(s, [
    { text: "Nothing leaves the machine", options: { bullet: true, breakLine: true } },
    { text: "Tests before code", options: { bullet: true, breakLine: true } },
    { text: "A second AI checks", options: { bullet: true, breakLine: true } },
    { text: "Honest verdict at the top", options: { bullet: true } },
  ], { x: 10.55, y: 2.55, w: 2.05, h: 3.2, fontSize: 14, paraSpaceAfter: 8 });
  inShort(s, "you only act at step 1 and step 5. Steps 2–4 run on their own.");
  s.addNotes("Pick a small, safe ticket that finishes in a few minutes. Have a finished run open in another tab in case the live one is slow.");
}

// ========== 13. Next ==========
{
  const s = pres.addSlide({ masterName: "DARK" });
  s.addText("What is next", { x: 0.8, y: 0.6, w: 11.7, h: 0.9, fontSize: 40, bold: true, color: C.background1, fontFace: THEME.headFontFace, margin: 0, isTextBox: true });
  s.addText("The tool works. What is left is people, not code.", { x: 0.8, y: 1.45, w: 11.7, h: 0.5, fontSize: 20, color: C.accent3, margin: 0, isTextBox: true });
  const cols = [
    ["Next steps", ["Publish one number a month: work shipped vs problems caused", "Hand the model service to IT ops, with someone on call", "Train a second operator", "Test bigger local models after the GPU upgrade"]],
    ["What I learned", ["The limit was the design, not the model", "The IASA canvases made the argument checkable — one page, not a long thread", "A tool one person can run is not yet a tool the company owns"]],
  ];
  cols.forEach(([h, items], i) => {
    const x = 0.8 + i * 6.0;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 2.3, w: 5.6, h: 3.4, fill: { color: "2A6274" }, rectRadius: 0.1, objectName: "Panel" });
    s.addText(h, { x: x + 0.35, y: 2.5, w: 5.0, h: 0.5, fontSize: 22, bold: true, color: C.accent2, margin: 0, isTextBox: true });
    s.addText(items.map((t, j) => ({ text: t, options: { bullet: true, breakLine: j < items.length - 1 } })),
      { x: x + 0.35, y: 3.1, w: 4.95, h: 2.4, fontSize: 16, color: C.background1, paraSpaceAfter: 10, valign: "top", margin: 0, isTextBox: true });
  });
  s.addText("One rule for the whole year: nothing moves work off our own hardware.", { x: 0.8, y: 6.0, w: 11.7, h: 0.4, fontSize: 15, italic: true, color: C.accent3, margin: 0, isTextBox: true });
  s.addNotes("Close by asking: who would own the model service, and who would be the second operator?");
}

(async () => {
  const out = process.argv[2] || "AIForge-IASA-Demo.pptx";
  await pres.writeFile({ fileName: out });
  await applyTheme(out, THEME);
  console.log("wrote", out);
})();
