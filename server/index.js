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
            text: `You are a furniture analysis expert helping shippers estimate item specs.
Analyze this image and respond with ONLY valid JSON in this exact format:
{
  "itemType": "name of the furniture item",
  "width": "estimated width in inches (number only)",
  "height": "estimated height in inches (number only)",
  "depth": "estimated depth in inches (number only)",
  "weightLbs": "estimated weight in lbs (number only)",
  "confidence": "confidence percentage 0-100 (number only)",
  "fragility": "Low | Medium | High",
  "handlingNotes": "one sentence of handling advice",
  "tags": ["tag1", "tag2", "tag3"]
}
If you cannot identify furniture in the image, return:
{ "error": "No furniture detected" }`
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
