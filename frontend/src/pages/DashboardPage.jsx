import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import api from '../api/client';

const SEVERITY_CLASSES = {
  critical: 'bg-red-100 text-red-800',
  high: 'bg-orange-100 text-orange-800',
  medium: 'bg-yellow-100 text-yellow-800',
  low: 'bg-green-100 text-green-800',
};

function SeverityBadge({ severity }) {
  const cls = SEVERITY_CLASSES[severity?.toLowerCase()] || 'bg-slate-100 text-slate-600';
  return (
    <span className={`rounded px-2 py-0.5 text-xs font-semibold uppercase ${cls}`}>{severity}</span>
  );
}

export default function DashboardPage() {
  const [alerts, setAlerts] = useState([]);
  const [incidents, setIncidents] = useState([]);
  const [health, setHealth] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    const load = async () => {
      try {
        const [alertsResponse, healthResponse, incidentsResponse] = await Promise.all([
          api.get('/api/alerts'),
          api.get('/api/health'),
          api.get('/api/incidents', { params: { status: 'open', take: 5 } }),
        ]);
        setAlerts(alertsResponse.data);
        setHealth(healthResponse.data);
        setIncidents(incidentsResponse.data.incidents || []);
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

  const incidentSeverityCounts = useMemo(() => {
    return incidents.reduce(
      (acc, inc) => {
        const key = inc.severity?.toLowerCase() || 'unknown';
        acc[key] = (acc[key] || 0) + 1;
        return acc;
      },
      { critical: 0, high: 0, medium: 0, low: 0 }
    );
  }, [incidents]);

  return (
    <div className="space-y-6">
      {error && <p className="rounded bg-red-100 px-3 py-2 text-sm text-red-700">{error}</p>}

      {/* Health widgets */}
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

      {/* Alert severity breakdown */}
      <div className="grid gap-4 md:grid-cols-4">
        {Object.entries(severityCounts).map(([severity, count]) => (
          <div key={severity} className="rounded border border-slate-200 bg-white p-3 text-sm shadow-sm">
            <p className="uppercase tracking-wide text-slate-500">{severity}</p>
            <p className="text-lg font-semibold text-slate-900">{count}</p>
          </div>
        ))}
      </div>

      {/* Open incidents summary */}
      <section className="rounded bg-white p-4 shadow">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-slate-900">
            Open incidents ({incidents.length})
          </h2>
          <div className="flex gap-2">
            {Object.entries(incidentSeverityCounts)
              .filter(([, c]) => c > 0)
              .map(([sev, count]) => (
                <span
                  key={sev}
                  className={`rounded px-2 py-0.5 text-xs font-semibold uppercase ${SEVERITY_CLASSES[sev] || 'bg-slate-100 text-slate-600'}`}
                >
                  {count} {sev}
                </span>
              ))}
            <Link
              to="/incidents"
              className="ml-2 rounded bg-indigo-600 px-3 py-1 text-xs font-medium text-white hover:bg-indigo-700"
            >
              View all
            </Link>
          </div>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-full text-left text-sm">
            <thead className="border-b bg-slate-50 text-slate-600">
              <tr>
                <th className="px-3 py-2">Severity</th>
                <th className="px-3 py-2">Title</th>
                <th className="px-3 py-2">Rule Type</th>
                <th className="px-3 py-2">Source IP</th>
                <th className="px-3 py-2">Events</th>
                <th className="px-3 py-2">Last Seen</th>
              </tr>
            </thead>
            <tbody>
              {incidents.map((inc) => (
                <tr key={inc.id} className="border-b">
                  <td className="px-3 py-2">
                    <SeverityBadge severity={inc.severity} />
                  </td>
                  <td className="px-3 py-2">{inc.title}</td>
                  <td className="px-3 py-2 text-slate-600">{inc.ruleType.replace('_', ' ')}</td>
                  <td className="px-3 py-2 font-mono text-xs">{inc.sourceIp || '-'}</td>
                  <td className="px-3 py-2 text-right">{inc.eventCount}</td>
                  <td className="px-3 py-2 text-xs text-slate-500">
                    {new Date(inc.lastSeen).toLocaleString()}
                  </td>
                </tr>
              ))}
              {incidents.length === 0 && (
                <tr>
                  <td className="px-3 py-4 text-slate-500" colSpan={6}>
                    No open incidents.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      {/* Recent alerts */}
      <section className="rounded bg-white p-4 shadow">
        <h2 className="mb-4 text-lg font-semibold text-slate-900">Recent alerts</h2>
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
                  <td className="px-3 py-2">
                    <SeverityBadge severity={alert.severity} />
                  </td>
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
