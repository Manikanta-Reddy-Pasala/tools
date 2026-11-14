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
| `IASA-Canvases-with-AIForge.pptx` / `.pdf` | **Canvas guide.** 20 slides: how canvases help, the canvas map, then 14 IASA canvases each drawn in its own shape and filled in for AIForge |
| `build_canvases_deck.js` | pptxgenjs script that builds the canvas guide |

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

## Canvas guide flow

1. Title
2. How canvases help: six reasons
3. The canvases at a glance: five questions (why, who, what, how, where next)
4. Our example: AIForge
5. Business Model Canvas
6. Persona Card
7. Customer Journey Map
8. Power / Interest Grid
9. Use Case Card
10. Context View
11. Service Blueprint
12. Business Capability Map
13. Capability Card
14. ASR Card
15. QATT Card
16. Decision Record (ADR)
17. OKR Card
18. Roadmap Canvas
19. How the canvases connect
20. What to take away

Every canvas slide has the same frame: left, what the canvas is and how it
helps; right, the canvas itself with the AIForge example in it.

```bash
SKILL=<pptx skill scripts dir> node build_canvases_deck.js IASA-Canvases-with-AIForge.pptx
```
