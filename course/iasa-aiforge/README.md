# AIForge — IASA Masterclass report-out

Course deck for the IASA Masterclass: how AIForge turns a ticket into a tested
pull request on machines we own, argued with the IASA canvases (persona,
customer journey, service blueprint, ASR, ADR, OKR, QATT).

| File | What it is |
|------|------------|
| `AIForge-IASA-Demo.pptx` | **Use this one for demos.** 13 slides, one idea per slide, an "In short" line on each, speaker notes, and a "Demo: what you will see" slide |
| `AIForge-IASA-Demo.pdf` | PDF of the demo deck |
| `original-AIForge-ReportOut.pptx` / `.pdf` | The original 29-slide course report-out |
| `build_deck.js` | pptxgenjs script that builds the demo deck |

## Demo deck flow

1. Title: what AIForge is in one sentence
2. The problem we had
3. What AIForge is: ticket → AIForge → pull request, plus a short glossary
4. Who it is for (Persona Card)
5. Before and after (Customer Journey)
6. How one ticket flows: the seven agents
7. What you see vs what runs behind (Service Blueprint)
8. Three things it must get right (ASR Cards)
9. Why we built our own (ADR)
10. What the numbers say (QATT Card)
11. Where we are today (OKR Card)
12. Demo: what you will see — five steps to follow live
13. What is next

## Rebuild

```bash
npm i pptxgenjs
SKILL=<path to the pptx skill scripts dir with apply_theme.js> node build_deck.js AIForge-IASA-Demo.pptx
```
