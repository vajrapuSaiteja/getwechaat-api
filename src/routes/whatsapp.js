import { Router } from 'express';
const router = Router();

// Incoming messages from WhatsApp provider (AiSensy/Wati)
router.post('/', (req, res) => {
  // TODO: verify webhook secret, parse message, route to bot logic
  res.sendStatus(200);
});

export default router;
