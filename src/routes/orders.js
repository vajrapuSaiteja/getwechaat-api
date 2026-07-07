import { Router } from 'express';
const router = Router();

router.get('/', (req, res) => {
  // TODO: fetch orders from Supabase
  res.json([]);
});

router.post('/', (req, res) => {
  // TODO: create order, generate invoice number (INV-YYYY-NNNN)
  res.status(201).json({});
});

export default router;
