import Fastify from 'fastify';
import cors from '@fastify/cors';
import { registerRoutes } from './routes';

const app = Fastify({ logger: true });

const port = Number(process.env.PORT || 4000);

async function main() {
  await app.register(cors, { origin: true });
  await registerRoutes(app);

  await app.listen({ port, host: '0.0.0.0' });
  app.log.info({ port }, 'API listening');
}

main().catch((err) => {
  app.log.error(err);
  process.exit(1);
});