# SOC Dashboard Frontend (React + Tailwind)

## Features

- Login page with JWT token handling
- Dashboard page for alerts and backend health widgets
- Logs viewer with search/filter powered by backend API
- React Router navigation and Axios integration

## Setup

```bash
cd frontend
cp .env.example .env
npm install
npm run dev
```

Frontend runs at `http://localhost:5173` by default.

## API Integration

Set backend URL with:

```bash
VITE_API_BASE_URL=http://localhost:4000
```

The app stores JWT in `localStorage` key `soc_token` and sends it as a Bearer token.
