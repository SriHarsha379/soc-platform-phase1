import { useEffect, useMemo, useState } from 'react';
import api from '../api/client';

export default function DashboardPage() {
  const [alerts, setAlerts] = useState([]);
  const [health, setHealth] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    const load = async () => {
      try {
        const [alertsResponse, healthResponse] = await Promise.all([
          api.get('/api/alerts'),
          api.get('/api/health'),
        ]);
        setAlerts(alertsResponse.data);
        setHealth(healthResponse.data);
      } catch (requestError) {
        setError(requestError.response?.data?.error || 'Failed to load dashboard data');
      }
    };

    load();
  }, []);

  const severityCounts = useMemo(() => {
    return alerts.reduce(
      (acc, alert) => {
        const key = alert.severity?.toLowerCase() || 'unknown';
        acc[key] = (acc[key] || 0) + 1;
        return acc;
      },
      { critical: 0, high: 0, medium: 0, low: 0 }
    );
  }, [alerts]);

  return (
    <div className="space-y-6">
      <div className="grid gap-4 md:grid-cols-3">
        <div className="rounded bg-white p-4 shadow">
          <p className="text-sm text-slate-500">Backend status</p>
          <p className="mt-2 text-xl font-semibold text-slate-900">{health?.status || 'unknown'}</p>
        </div>
        <div className="rounded bg-white p-4 shadow">
          <p className="text-sm text-slate-500">Backend uptime</p>
          <p className="mt-2 text-xl font-semibold text-slate-900">
            {health ? `${Math.floor(health.uptime)}s` : 'n/a'}
          </p>
        </div>
        <div className="rounded bg-white p-4 shadow">
          <p className="text-sm text-slate-500">Open alerts</p>
          <p className="mt-2 text-xl font-semibold text-slate-900">{alerts.length}</p>
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-4">
        {Object.entries(severityCounts).map(([severity, count]) => (
          <div key={severity} className="rounded border border-slate-200 bg-white p-3 text-sm shadow-sm">
            <p className="uppercase tracking-wide text-slate-500">{severity}</p>
            <p className="text-lg font-semibold text-slate-900">{count}</p>
          </div>
        ))}
      </div>

      <section className="rounded bg-white p-4 shadow">
        <h2 className="mb-4 text-lg font-semibold text-slate-900">Recent alerts</h2>
        {error && <p className="mb-3 rounded bg-red-100 px-3 py-2 text-sm text-red-700">{error}</p>}
        <div className="overflow-x-auto">
          <table className="min-w-full text-left text-sm">
            <thead className="border-b bg-slate-50 text-slate-600">
              <tr>
                <th className="px-3 py-2">Severity</th>
                <th className="px-3 py-2">Title</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2">Source</th>
                <th className="px-3 py-2">Created</th>
              </tr>
            </thead>
            <tbody>
              {alerts.map((alert) => (
                <tr key={alert.id} className="border-b">
                  <td className="px-3 py-2 font-medium uppercase">{alert.severity}</td>
                  <td className="px-3 py-2">{alert.title}</td>
                  <td className="px-3 py-2">{alert.status}</td>
                  <td className="px-3 py-2">{alert.source || '-'}</td>
                  <td className="px-3 py-2">{new Date(alert.createdAt).toLocaleString()}</td>
                </tr>
              ))}
              {alerts.length === 0 && (
                <tr>
                  <td className="px-3 py-4 text-slate-500" colSpan={5}>
                    No alerts found.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
