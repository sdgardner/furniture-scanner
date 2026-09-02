import express from 'express';
import cors from 'cors';
import Anthropic from '@anthropic-ai/sdk';

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' }));

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

app.get('/health', (req, res) => res.json({ ok: true }));

app.post('/detect', async (req, res) => {
  const { images, image } = req.body;
  const photoList = images?.length ? images : image ? [image] : [];
  if (!photoList.length) return res.status(400).json({ error: 'No image' });

  const base64 = photoList[0].replace(/^data:image\/\w+;base64,/, '');
  const mediaType = photoList[0].match(/^data:(image\/\w+);base64,/)?.[1] || 'image/jpeg';

  try {
    const response = await client.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 5,
      temperature: 0,
      messages: [{
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: mediaType, data: base64 } },
          { type: 'text', text: 'Is this "furniture" (household/office items like sofas, tables, dressers) or "machinery" (equipment, vehicles, industrial machines like excavators, generators, forklifts)? Reply with exactly one word: furniture or machinery.' }
        ]
      }]
    });
    const text = response.content[0].text.trim().toLowerCase();
    const category = text.includes('machin') ? 'machinery' : 'furniture';
    console.log('Detected category:', category, '| raw:', text);
    res.json({ category });
  } catch (err) {
    console.error('Detect error:', err.message);
    res.status(500).json({ error: 'Detection failed', detail: err.message });
  }
});

app.post('/analyze', async (req, res) => {
  const { images, image, category, materials, material, materialDensity, condition } = req.body;

  const photoList = images?.length ? images : image ? [image] : [];
  if (!photoList.length) return res.status(400).json({ error: 'No image provided' });

  const imageBlocks = photoList.map(dataUrl => {
    const base64 = dataUrl.replace(/^data:image\/\w+;base64,/, '');
    const mediaType = dataUrl.match(/^data:(image\/\w+);base64,/)?.[1] || 'image/jpeg';
    return { type: 'image', source: { type: 'base64', media_type: mediaType, data: base64 } };
  });

  const matList = materials?.length ? materials : (material ? [material] : []);
  const knownMats = matList.filter(m => m !== 'Unknown' && m !== 'Not Sure');
  const materialHint = knownMats.length
    ? `\nThe user identified the material(s) as: ${knownMats.join(' + ')}${materialDensity ? ` (blended density ≈ ${materialDensity} lbs/cu ft)` : ''}. Account for heavier materials dominating the weight.`
    : '';

  const photoNote = photoList.length > 1
    ? `\nYou have ${photoList.length} photos — use them together for better depth/width/height estimates.`
    : '';

  try {
    const response = await client.messages.create({
      model: 'claude-sonnet-4-6',
      max_tokens: 1024,
      temperature: 0,
      messages: [{
        role: 'user',
        content: [
          ...imageBlocks,
          {
            type: 'text',
            text: `You are a shipping and logistics expert who analyzes images to identify items and provide accurate size, weight, and handling estimates for carriers.${photoNote}${materialHint}

STEP 1 — Classify the item:${category ? `\nThe user has already told you this is: "${category}" — use this as a strong hint and set itemCategory accordingly.` : `
- "furniture": household or office items (sofas, dressers, tables, chairs, appliances, etc.)
- "machinery": industrial or commercial equipment (construction machines, generators, engines, forklifts, farm equipment, vehicles, compressors, pumps, etc.)`}${condition ? `\nThe user noted the machinery condition is: ${condition}.` : ''}

STEP 2 — Use every visual clue for scale:
- Coin (US quarter = 0.955" diameter), banana (7-8" long), water bottle (10-11" tall)
- Hand span ~7-8", foot ~10"
- Doorways ~80" tall, 32-36" wide; ceiling ~96-108"; outlets/switches ~4.5" tall
- For machinery: tires, cab windows, hydraulic cylinders, and standard component sizes
- Furniture proportions: drawer heights, cushion depths, leg heights

STEP 3 — Estimate dimensions and weight:
- Dimensions always in inches
- **IMPORTANT: If you identified the brand and model number, use the manufacturer's published specifications for that exact model — do NOT visually estimate. For example, a CAT 305E mini excavator has published specs: operating weight ~11,464 lbs, width ~66 inches, height ~98 inches, length ~196 inches with boom lowered. Always prefer known specs over visual guessing.**
- If model is unknown, use visual clues and these density references:${materialDensity ? `\n- Use ${materialDensity} lbs/cu ft for weight calculation` : `
- Density references: solid wood ~45, upholstered ~22, particleboard ~35, metal ~90, marble ~160, cast iron ~450 lbs/cu ft
- Machinery weight references: CAT 305E mini excavator ~11,500 lbs, compact skid steer ~6,000 lbs, full excavator (CAT 320) ~48,000 lbs, large generator ~2,000–10,000 lbs`}

STEP 4 — For machinery, recommend the appropriate trailer:
- "standard": small equipment under 3,000 lbs, fits in a cargo van or pickup
- "enclosed": sensitive or weather-sensitive equipment needing full protection
- "flatbed": the default for most construction equipment — mini excavators, skid steers, small bulldozers, forklifts, generators, tractors, anything that fits within standard height/width limits (under ~8.5 ft tall loaded, under 48,000 lbs)
- "lowboy": ONLY for full-size heavy equipment that is too tall for a standard flatbed — large excavators (CAT 320 and up, 20+ tons), large cranes, large bulldozers (D6 and up). A mini excavator like a CAT 305E or 308 is a FLATBED, not a lowboy.
- "RGN": extremely oversized or overweight loads over 48,000 lbs requiring a detachable neck for drive-on loading

Respond with ONLY valid JSON, no markdown, no code fences. The "analysis" field comes FIRST — work through your scale reasoning there BEFORE committing to any numbers:
{
  "analysis": "2-4 sentences: what the item is, which visual scale references you found (doorway, outlet, known-size objects), and how you derived the dimensions from them. If you matched a standard manufactured size, say which.",
  "itemCategory": "furniture" or "machinery",
  "itemType": "specific name of the item",
  "brand": "manufacturer brand name if identifiable (e.g. 'Caterpillar', 'John Deere', 'Kubota', 'Bobcat') or null",
  "modelNumber": "model number/name if visible (e.g. '305E', 'D6T', '320GC') or null",
  "manufacturerYear": <estimated manufacture year as a number, or null — use serial plates, cab design generation, or color scheme to estimate>,
  "width": <width in inches as a number>,
  "height": <height in inches as a number>,
  "depth": <depth in inches as a number>,
  "weightLbs": <weight in lbs — use published operating weight if model is known, otherwise estimate>,
  "confidence": <confidence 0-100 as a number>,
  "fragility": "Low | Medium | High",
  "handlingNotes": "one practical sentence of handling advice for the carrier",
  "trailerType": "standard | flatbed | lowboy | RGN | enclosed",
  "tags": ["include brand name if known", "include model number if known", "include estimated year if known", "plus any other relevant tags"]
}
If you cannot identify the item, return:
{"error": "No item detected"}`
          }
        ]
      }]
    });

    const raw = response.content[0].text.trim();
    const text = raw.replace(/^```json\s*/i, '').replace(/^```\s*/i, '').replace(/```\s*$/, '').trim();
    const json = JSON.parse(text);
    res.json(json);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Analysis failed', detail: err.message });
  }
});

app.post('/inventory', async (req, res) => {
  const { frames } = req.body;
  if (!frames?.length) return res.status(400).json({ error: 'No video frames provided' });

  const frameList = frames.slice(0, 24);
  const imageBlocks = frameList.map(dataUrl => {
    const base64 = dataUrl.replace(/^data:image\/\w+;base64,/, '');
    const mediaType = dataUrl.match(/^data:(image\/\w+);base64,/)?.[1] || 'image/jpeg';
    return { type: 'image', source: { type: 'base64', media_type: mediaType, data: base64 } };
  });

  try {
    const response = await client.messages.create({
      model: 'claude-sonnet-4-6',
      max_tokens: 6000,
      temperature: 0,
      messages: [{
        role: 'user',
        content: [
          ...imageBlocks,
          {
            type: 'text',
            text: `You are a professional moving-survey estimator. These ${frameList.length} frames were sampled IN ORDER from one continuous walkthrough video of a home or space.

Build a deduplicated inventory of every shippable household item visible across all frames.

SCALE CALIBRATION FIRST: the user was instructed to start each room by filming its doorway head-on. Look for interior doorways in the earliest frames of each room — a standard interior door is 80" tall and 32-36" wide (most commonly 32"). Establish pixels-per-inch from that doorframe and carry the calibration through that room's items, adjusting for how much closer or farther each item is than the door.

CRITICAL — deduplication: the camera moves through the space, so the SAME physical item appears in multiple consecutive frames from different angles. Count each physical item exactly ONCE. Identical multiples (e.g. 4 matching dining chairs) go on one line with qty.

Include: furniture, appliances, TVs/electronics, rugs, mirrors, large boxes, exercise equipment, and anything else a mover would put on a truck.
Ignore: built-in fixtures (cabinets, countertops, ceiling lights), walls/doors/windows, people and pets, and small loose items under ~5 lbs unless they are boxed.

For each item:
- Estimate dimensions in inches and weight in lbs, using standard visual references for scale (interior doorways ~80" tall and 32-36" wide, outlets/switches ~4.5" tall, sofa seat height ~18", countertops ~36" high).
- Pick the dominant material from EXACTLY this list: wood, upholstered, particleboard, metal, castiron, marble, glass, unknown.
- Estimate movers needed: 1, 2, or 3 (3 means 3+).
- Name the room it was seen in (e.g. "Living Room", "Bedroom", "Garage"). If unclear, use "Unknown".
- Give a per-item confidence 0-100 covering BOTH the identification and the measurements. Be honest: an item seen only once, partially, blurry, or at a weird angle should score below 70.

MEASUREMENT DISCIPLINE — most item types come in a FAMILY of standard manufactured sizes. Your job is a two-step process:
(1) identify the item type to get its size family, then
(2) use your visual scale anchors (doorways, outlets, countertops, adjacent items) to pick WHICH member of the family this one is.
NEVER default to the most common or middle size — that is the #1 error. A desk identified without careful anchor comparison gets called 60×30 when it is actually a compact 48×24. Compare the item's width to the nearest doorway or desk chair before choosing.

Size families:
- Desks: compact 40×20, small 48×24, standard 60×30, large 66×30, executive 72×36 (all 29-30"H)
- Sofas: loveseat 52-64"W, apartment 68-76"W, standard 78-88"W (30-36"D, 30-36"H)
- Posters/banners/framed art: 12×18, 18×24, 24×36, 27×40 — judge against nearby outlets/switches (4.5"H)
- Soundbars: compact 24-32"W, standard 35-45"W (always 2-4"H, 3-5"D)
- TV / media consoles: small 47-58"W, standard 58-70"W (15-20"D, 20-30"H)
- Bookcases: 24/30/36"W × 11-13"D; heights 30/48/72"
- Filing cabinets: 15"W × 28"D; 2-drawer 28"H, 4-drawer 52"H; lateral files 30/36/42"W
- TVs: judge the diagonal against the console below (43/50/55/65/75") — a 65" TV is ~57"W × 33"H × 3"D
- Dining tables 28-30"H; coffee tables 16-18"H; office chairs ~26×26", 38-45"H
- Refrigerators 30-36"W × 66-70"H; washers/dryers 27"W × 38-43"H; mattresses: twin 38×75, full 54×75, queen 60×80, king 76×80

BIAS WARNING: visual estimates systematically skew LARGE, especially for items seen at an angle or filling the frame. When your anchors leave you torn between two sizes in a family, pick the SMALLER one. In offices and homes, the compact variant is more common than the showroom variant.
Use pure visual estimation only for items with no standard size, and apply the same skew-small correction.

Respond with ONLY valid JSON, no markdown, no code fences. The "analysis" field comes FIRST — establish your scale anchors there BEFORE estimating any item:
{
  "analysis": "3-5 sentences: which rooms the walkthrough covers, which scale anchors you found (doorways, outlets, countertops, known-size items like TVs whose diagonal you can judge), and roughly how many pixels-per-inch those anchors imply in typical frames. Note any items you could only glimpse.",
  "items": [
    { "itemType": "specific item name", "room": "Living Room", "qty": 1, "width": <inches>, "height": <inches>, "depth": <inches>, "weightLbs": <lbs>, "material": "wood", "crew": 1, "fragility": "Low | Medium | High", "confidence": <0-100>, "frameIndex": <0-based index of the single frame where this item is most clearly visible — frames are numbered 0 to ${frameList.length - 1} in the order given>, "box": { "x": <left edge as % of frame width 0-100>, "y": <top edge as % of frame height 0-100>, "w": <width %>, "h": <height %> } }
  ],
  "confidence": <overall confidence 0-100>
}
Cross-check every item against its scale anchor AND against neighboring items — a soundbar cannot be taller than the TV console it sits on; a desk cannot be taller than the person-height doorway behind it. Fix any inconsistency before answering.
If no shippable items are visible in any frame, return: {"error": "No items detected"}`
          }
        ]
      }]
    });

    const raw = response.content[0].text.trim();
    const text = raw.replace(/^```json\s*/i, '').replace(/^```\s*/i, '').replace(/```\s*$/, '').trim();
    const json = JSON.parse(text);
    console.log('Inventory:', json.items?.length ?? 0, 'items from', frameList.length, 'frames');
    res.json(json);
  } catch (err) {
    console.error('Inventory error:', err.message);
    res.status(500).json({ error: 'Inventory analysis failed', detail: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
