# SOC Dashboard Backend (Express + Prisma + Elasticsearch)

## Features

- JWT authentication (`POST /api/auth/login`)
- Role-based access (`admin`, `analyst`)
- Alerts API from PostgreSQL via Prisma (`GET /api/alerts`)
- Logs API from Elasticsearch with search/filter (`GET /api/logs`)

## Setup

```bash
cd backend
cp .env.example .env
npm install
npx prisma migrate dev --name init
npm run db:seed
npm run dev
```

Backend runs at `http://localhost:4000` by default.

## Default users (seeded)

- Admin: `admin@soc.local` / `Admin@123`
- Analyst: `analyst@soc.local` / `Analyst@123`

## API Endpoints

- `POST /api/auth/login`
- `GET /api/auth/me`
- `GET /api/alerts?severity=critical&status=open`
- `GET /api/logs?q=failed+login&level=10&source=web-01&from=0&size=25`
- `GET /api/health`

All endpoints except login require `Authorization: Bearer <JWT>`.
