import express from 'express';
import cors from 'cors';
import Anthropic from '@anthropic-ai/sdk';

const app = express();
app.use(cors());
app.use(express.json({ limit: '20mb' }));

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

app.get('/health', (req, res) => res.json({ ok: true }));

app.post('/analyze', async (req, res) => {
  const { image } = req.body; // base64 image data URL
  if (!image) return res.status(400).json({ error: 'No image provided' });

  // Strip the data URL prefix to get raw base64
  const base64 = image.replace(/^data:image\/\w+;base64,/, '');
  const mediaType = image.match(/^data:(image\/\w+);base64,/)?.[1] || 'image/jpeg';

  try {
    const response = await client.messages.create({
      model: 'claude-sonnet-4-6',
      max_tokens: 1024,
      messages: [{
        role: 'user',
        content: [
          {
            type: 'image',
            source: { type: 'base64', media_type: mediaType, data: base64 },
          },
          {
            type: 'text',
            text: `You are a furniture measurement expert helping shippers get accurate size and weight estimates.

Analyze this image carefully using every visual clue available:
- If a coin is visible, use it as a scale reference (a US quarter is 0.955" diameter)
- If a banana is visible, use it as a scale reference (a typical banana is 7-8" long)
- If a standard water bottle is visible, use it as a scale reference (typically 10-11" tall)
- If a hand or foot is visible, use it as a scale reference (average hand span ~7-8", foot ~10")
- Use standard room features for scale: doorways are typically 80" tall and 32-36" wide, ceiling heights are typically 96-108", electrical outlets are 4.5" tall, light switches are 4.5" tall
- Use the furniture's own proportions — drawer heights, cushion depths, leg heights all have standard sizes
- Look at flooring tiles/planks, baseboards, and wall features for additional scale
- Cross-check your estimates: does the weight make sense for the material and size? (solid wood = ~45 lbs/cu ft, upholstered = ~25 lbs/cu ft, metal = ~100 lbs/cu ft)

Respond with ONLY valid JSON, no markdown, no code fences:
{
  "itemType": "specific name of the furniture item",
  "width": <width in inches as a number>,
  "height": <height in inches as a number>,
  "depth": <depth in inches as a number>,
  "weightLbs": <estimated weight in lbs as a number>,
  "confidence": <confidence 0-100 as a number>,
  "fragility": "Low | Medium | High",
  "handlingNotes": "one practical sentence of handling advice for shippers",
  "tags": ["tag1", "tag2", "tag3"]
}
If you cannot identify furniture in the image, return:
{"error": "No furniture detected"}`
          }
        ]
      }]
    });

    const raw = response.content[0].text.trim();
    const text = raw.replace(/^```json\s*/i, '').replace(/^```\s*/i, '').replace(/```\s*$/,'').trim();
    const json = JSON.parse(text);
    res.json(json);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Analysis failed', detail: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
