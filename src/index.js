import 'dotenv/config';
import express from 'express';
import whatsappRoutes from './routes/whatsapp.js';
import productRoutes from './routes/products.js';
import orderRoutes from './routes/orders.js';

const app = express();
app.use(express.json());

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.use('/webhook/whatsapp', whatsappRoutes);
app.use('/api/products', productRoutes);
app.use('/api/orders', orderRoutes);

const port = process.env.PORT || 4000;
app.listen(port, () => console.log(`getwechaat-api running on port ${port}`));
