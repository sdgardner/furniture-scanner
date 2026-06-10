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
- Weight in lbs (machinery can be thousands or tens of thousands)${materialDensity ? `\n- Use ${materialDensity} lbs/cu ft for weight calculation` : `
- Density references: solid wood ~45, upholstered ~22, particleboard ~35, metal ~90, marble ~160, cast iron ~450 lbs/cu ft
- Machinery references: compact skid steer ~6,000 lbs, full excavator ~40,000 lbs, large generator ~2,000-10,000 lbs`}

STEP 4 — For machinery, recommend the appropriate trailer:
- "standard": small equipment under 3,000 lbs, fits in a cargo van or pickup
- "enclosed": sensitive or weather-sensitive equipment needing full protection
- "flatbed": the default for most construction equipment — mini excavators, skid steers, small bulldozers, forklifts, generators, tractors, anything that fits within standard height/width limits (under ~8.5 ft tall loaded, under 48,000 lbs)
- "lowboy": ONLY for full-size heavy equipment that is too tall for a standard flatbed — large excavators (CAT 320 and up, 20+ tons), large cranes, large bulldozers (D6 and up). A mini excavator like a CAT 305E or 308 is a FLATBED, not a lowboy.
- "RGN": extremely oversized or overweight loads over 48,000 lbs requiring a detachable neck for drive-on loading

Respond with ONLY valid JSON, no markdown, no code fences:
{
  "itemCategory": "furniture" or "machinery",
  "itemType": "specific name of the item",
  "modelNumber": "model number/name if visible on the item (e.g. '305E', 'D6T', '320GC') or null",
  "manufacturerYear": <estimated manufacture year as a number, or null if not determinable — for machinery, use visible serial number plates, design generation, or cab style to estimate>,
  "width": <width in inches as a number>,
  "height": <height in inches as a number>,
  "depth": <depth in inches as a number>,
  "weightLbs": <estimated weight in lbs as a number — if you identified the model number, use the known published operating weight for that model>,
  "confidence": <confidence 0-100 as a number>,
  "fragility": "Low | Medium | High",
  "handlingNotes": "one practical sentence of handling advice for the carrier",
  "trailerType": "standard | flatbed | lowboy | RGN | enclosed",
  "tags": ["tag1", "tag2", "tag3"]
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

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
