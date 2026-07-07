import { Router } from 'express';
const router = Router();

router.get('/', (req, res) => {
  // TODO: fetch products from Supabase
  res.json([]);
});

export default router;
