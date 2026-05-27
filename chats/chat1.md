# Furniture Measurement App

_Started 2026-05-27 14:20 UTC_

---

## User

can you create an app where you can take a photo of furniture and it gives you estimates on weight and size

## Assistant

_[tool: questions_v2]_

## User

Questions answered:
- audience: Shipper (person moving furniture)
- platform: Both mobile + web
- flow: All of the above
- output_detail: Weight estimate (lbs), Fragility / handling notes, Dimensions (L × W × H), Confidence score, Item category / type label
- multi_item: Both modes
- num_screens: Full flow (camera → processing → result → next step)
- variations: Different result layouts (card, list, measurement callouts), Different camera/capture UI (guided frame, AR overlay, upload), Different levels of detail shown, Different flows (instant vs. step-by-step), Novel / unexpected approaches

## Assistant

_[tool: update_todos]_

_[tool: list_files]_

_[tool: copy_starter_component]_

_[tool: copy_starter_component]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: list_files]_

_[tool: read_file]_

Let me read the design_canvas to understand its API, then I'll build all wireframes.

_[tool: update_todos]_

_[tool: write_file]_

Now I have everything I need. Let me build all 8 wireframe screens.

_[tool: done]_

_[tool: fork_verifier_agent]_

_[tool: update_todos]_

Here's what's on the canvas — **8 wireframe screens across 3 sections:**

**01 · Capture UI**
- **A · AR Live Overlay** — real-time bounding box with floating dimension callouts and weight chip; instant, no steps
- **B · Guided Step-by-Step** — progress indicator, corner-guide frame, shutter button; good for first-time users
- **C · Web Upload** — drag-and-drop zone or camera open; web-native flow

**02 · Results UI**
- **D · Instant Card** — 2×2 stat grid (weight, W×H×D), confidence bar, handling notes, CTAs
- **E · Photo + Callouts** — dimensions overlaid directly on the photo with color-coded arrows (width=blue, height=orange)
- **F · Detailed Specs List** — full spec table with thumbnail, every field broken out row-by-row

**03 · Multi-item & Next Steps**
- **G · Room Scan** — multiple bounding boxes color-coded by item, scrollable list below, "Post All"
- **H · Post-Scan** — action cards (Post Shipment, Save to Inventory, Share), plus saved items list

**Next decisions to make:**
- Which capture approach resonates — AR instant, guided steps, or upload?
- Which result layout do you prefer — card, callouts, or list?
- Should we add a **processing / loading state** screen?
- Ready to go hi-fi on any of these? I can build a clickable prototype next.

## User

number 2

## Assistant

Just want to make sure I'm picking the right one — do you mean:

- **B · Guided Step-by-Step** (the capture UI with the progress bar + corner guides), or
- **E · Photo + Callouts** (the result screen with dimension arrows overlaid on the photo)?

## User

I like are they different flows?

## Assistant

They're actually two different **stages** of the same flow — you'd use them back to back:

1. **B · Guided Capture** → how you *take* the photo (step indicator, corner guides, shutter)
2. **E · Photo + Callouts** → what you *see after* AI processes it (your photo with dimension arrows + weight chip overlaid)

Together they make a nice coherent flow: **Capture → Processing → Callout Result → Post Shipment.**

Want me to build that out as a full hi-fi clickable prototype — all the way from the camera screen through to the "Post Shipment" hand-off? I can add the processing/loading state in between too.

## User

can you build this as a high-fi prototype using skid

## Assistant

_[tool: update_todos]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: list_files]_

_[tool: copy_files]_

_[tool: copy_starter_component]_

Now let me copy the fonts, CSS files, and logo, then build the hi-fi prototype.

_[tool: read_file]_

Let me check the tweaks panel API before building.

_[tool: write_file]_

## Assistant

_[tool: write_file]_

_[tool: done]_

_[tool: fork_verifier_agent]_

Here's the hi-fi prototype — a fully clickable 5-screen mobile app built on Skid:

**Flow:**
1. **Home** — uShip header, hero with two CTAs, recent scans list
2. **Guided Capture** — Dark camera viewfinder, corner guides, scan animation, shutter button
3. **Processing** — Photo preview, animated progress bar + 4-step checklist (auto-advances)
4. **Results** — Sofa illustration with blue width arrow, orange height arrow, depth/weight chips; confidence bar, stats grid, handling alert
5. **Next Steps** — Summary card with tags, three action cards, "Scan Another Item" ghost CTA

**Tweaks panel** (toolbar toggle):
- Units: inches / cm
- Show/hide confidence score

**Next steps if you want to go further:**
- Connect the real Claude AI to actually analyze uploaded photos
- Add the room scan / multi-item mode (Wireframe G)
- Flesh out the "Post a Shipment" flow to hand off into the existing uShip quote flow
- Swap the sofa illustration for a real camera feed on a live device

## User

Verifier agent check completed

## Assistant

_[tool: str_replace_edit]_

Good catch. I'll gate the processing `useEffect` so it only runs when that screen is actually active.Now pass the `active` prop from the screens array:

_[tool: str_replace_edit]_

_[tool: done]_

_[tool: fork_verifier_agent]_

Fixed — the processing animation now only starts when you actually navigate to that screen, so the home screen stays put until you tap "Start Scanning."

