import { useEffect, useState } from 'react';
import api from '../api/client';

const SEVERITY_CLASSES = {
  critical: 'bg-red-100 text-red-800',
  high: 'bg-orange-100 text-orange-800',
  medium: 'bg-yellow-100 text-yellow-800',
  low: 'bg-green-100 text-green-800',
};

const STATUS_CLASSES = {
  open: 'bg-blue-100 text-blue-800',
  investigating: 'bg-purple-100 text-purple-800',
  resolved: 'bg-slate-100 text-slate-600',
};

function SeverityBadge({ severity }) {
  const cls = SEVERITY_CLASSES[severity?.toLowerCase()] || 'bg-slate-100 text-slate-600';
  return (
    <span className={`rounded px-2 py-0.5 text-xs font-semibold uppercase ${cls}`}>{severity}</span>
  );
}

function StatusBadge({ status }) {
  const cls = STATUS_CLASSES[status?.toLowerCase()] || 'bg-slate-100 text-slate-600';
  return (
    <span className={`rounded px-2 py-0.5 text-xs font-medium capitalize ${cls}`}>{status}</span>
  );
}

export default function IncidentsPage() {
  const [incidents, setIncidents] = useState([]);
  const [total, setTotal] = useState(0);
  const [filters, setFilters] = useState({ severity: '', status: '', ruleType: '' });
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [correlating, setCorrelating] = useState(false);
  const [correlateMessage, setCorrelateMessage] = useState('');

  const loadIncidents = async (params = {}) => {
    setLoading(true);
    setError('');
    try {
      const response = await api.get('/api/incidents', {
        params: {
          severity: params.severity || undefined,
          status: params.status || undefined,
          ruleType: params.ruleType || undefined,
        },
      });
      setIncidents(response.data.incidents || []);
      setTotal(response.data.total || 0);
    } catch (requestError) {
      setError(requestError.response?.data?.error || 'Failed to load incidents');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    api
      .get('/api/incidents')
      .then((response) => {
        setIncidents(response.data.incidents || []);
        setTotal(response.data.total || 0);
      })
      .catch((requestError) => {
        setError(requestError.response?.data?.error || 'Failed to load incidents');
      })
      .finally(() => setLoading(false));
  }, []);

  const handleFilterChange = (event) => {
    const { name, value } = event.target;
    const next = { ...filters, [name]: value };
    setFilters(next);
    loadIncidents(next);
  };

  const handleCorrelate = async () => {
    setCorrelating(true);
    setCorrelateMessage('');
    try {
      const response = await api.post('/api/incidents/correlate');
      setCorrelateMessage(`Correlation complete: ${response.data.triggered} incident(s) created/updated.`);
      await loadIncidents(filters);
    } catch (requestError) {
      setCorrelateMessage(requestError.response?.data?.error || 'Correlation failed');
    } finally {
      setCorrelating(false);
    }
  };

  const handleStatusUpdate = async (id, status) => {
    try {
      await api.patch(`/api/incidents/${id}`, { status });
      setIncidents((prev) =>
        prev.map((inc) => (inc.id === id ? { ...inc, status } : inc))
      );
    } catch (requestError) {
      setError(requestError.response?.data?.error || 'Failed to update incident status');
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3 rounded bg-white p-4 shadow">
        <h2 className="text-lg font-semibold text-slate-900">Incidents ({total})</h2>
        <div className="flex flex-wrap items-center gap-3">
          <select
            name="severity"
            value={filters.severity}
            onChange={handleFilterChange}
            className="rounded border border-slate-300 px-3 py-2 text-sm"
          >
            <option value="">All severities</option>
            <option value="critical">Critical</option>
            <option value="high">High</option>
            <option value="medium">Medium</option>
            <option value="low">Low</option>
          </select>

          <select
            name="status"
            value={filters.status}
            onChange={handleFilterChange}
            className="rounded border border-slate-300 px-3 py-2 text-sm"
          >
            <option value="">All statuses</option>
            <option value="open">Open</option>
            <option value="investigating">Investigating</option>
            <option value="resolved">Resolved</option>
          </select>

          <select
            name="ruleType"
            value={filters.ruleType}
            onChange={handleFilterChange}
            className="rounded border border-slate-300 px-3 py-2 text-sm"
          >
            <option value="">All rule types</option>
            <option value="brute_force">Brute force</option>
            <option value="traffic_spike">Traffic spike</option>
          </select>

          <button
            type="button"
            onClick={handleCorrelate}
            disabled={correlating}
            className="rounded bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
          >
            {correlating ? 'Running…' : 'Run Correlation'}
          </button>
        </div>
      </div>

      {correlateMessage && (
        <p className="rounded bg-indigo-50 px-4 py-2 text-sm text-indigo-800">{correlateMessage}</p>
      )}
      {error && <p className="rounded bg-red-100 px-4 py-2 text-sm text-red-700">{error}</p>}

      <section className="rounded bg-white shadow">
        {loading ? (
          <p className="p-6 text-sm text-slate-500">Loading incidents…</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-left text-sm">
              <thead className="border-b bg-slate-50 text-slate-600">
                <tr>
                  <th className="px-3 py-2">Severity</th>
                  <th className="px-3 py-2">Title</th>
                  <th className="px-3 py-2">Rule Type</th>
                  <th className="px-3 py-2">Source IP</th>
                  <th className="px-3 py-2">Host</th>
                  <th className="px-3 py-2">Events</th>
                  <th className="px-3 py-2">Status</th>
                  <th className="px-3 py-2">Last Seen</th>
                  <th className="px-3 py-2">Actions</th>
                </tr>
              </thead>
              <tbody>
                {incidents.map((inc) => (
                  <tr key={inc.id} className="border-b align-top hover:bg-slate-50">
                    <td className="px-3 py-2">
                      <SeverityBadge severity={inc.severity} />
                    </td>
                    <td className="max-w-xs px-3 py-2">
                      <p className="font-medium text-slate-900">{inc.title}</p>
                      <p className="mt-0.5 text-xs text-slate-500">{inc.description}</p>
                    </td>
                    <td className="px-3 py-2 text-slate-700">{inc.ruleType.replace('_', ' ')}</td>
                    <td className="px-3 py-2 font-mono text-xs">{inc.sourceIp || '-'}</td>
                    <td className="px-3 py-2">{inc.affectedHost || '-'}</td>
                    <td className="px-3 py-2 text-right">{inc.eventCount}</td>
                    <td className="px-3 py-2">
                      <StatusBadge status={inc.status} />
                    </td>
                    <td className="px-3 py-2 text-xs text-slate-500">
                      {new Date(inc.lastSeen).toLocaleString()}
                    </td>
                    <td className="px-3 py-2">
                      {inc.status !== 'resolved' && (
                        <div className="flex gap-1">
                          {inc.status === 'open' && (
                            <button
                              type="button"
                              onClick={() => handleStatusUpdate(inc.id, 'investigating')}
                              className="rounded bg-purple-100 px-2 py-0.5 text-xs text-purple-800 hover:bg-purple-200"
                            >
                              Investigate
                            </button>
                          )}
                          <button
                            type="button"
                            onClick={() => handleStatusUpdate(inc.id, 'resolved')}
                            className="rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-700 hover:bg-slate-200"
                          >
                            Resolve
                          </button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
                {incidents.length === 0 && (
                  <tr>
                    <td className="px-3 py-6 text-slate-500" colSpan={9}>
                      No incidents match the current filters.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
