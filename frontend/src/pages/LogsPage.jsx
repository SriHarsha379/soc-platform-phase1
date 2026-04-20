import { useState } from 'react';
import api from '../api/client';

export default function LogsPage() {
  const [filters, setFilters] = useState({ q: '', level: '', source: '' });
  const [logs, setLogs] = useState([]);
  const [total, setTotal] = useState(0);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleChange = (event) => {
    const { name, value } = event.target;
    setFilters((prev) => ({ ...prev, [name]: value }));
  };

  const searchLogs = async (event) => {
    event.preventDefault();
    setError('');
    setLoading(true);

    try {
      const response = await api.get('/api/logs', {
        params: {
          q: filters.q || undefined,
          level: filters.level || undefined,
          source: filters.source || undefined,
          size: 50,
        },
      });
      setLogs(response.data.results || []);
      setTotal(response.data.total || 0);
    } catch (requestError) {
      setError(requestError.response?.data?.error || 'Failed to fetch logs');
      setLogs([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-4">
      <form onSubmit={searchLogs} className="rounded bg-white p-4 shadow">
        <h2 className="mb-4 text-lg font-semibold text-slate-900">Logs Viewer</h2>
        <div className="grid gap-3 md:grid-cols-4">
          <input
            name="q"
            placeholder="Search query"
            value={filters.q}
            onChange={handleChange}
            className="rounded border border-slate-300 px-3 py-2"
          />
          <input
            name="level"
            placeholder="Rule level (e.g. 10)"
            value={filters.level}
            onChange={handleChange}
            className="rounded border border-slate-300 px-3 py-2"
          />
          <input
            name="source"
            placeholder="Agent name"
            value={filters.source}
            onChange={handleChange}
            className="rounded border border-slate-300 px-3 py-2"
          />
          <button className="rounded bg-blue-600 px-4 py-2 font-medium text-white hover:bg-blue-700" type="submit">
            {loading ? 'Searching...' : 'Search'}
          </button>
        </div>
        {error && <p className="mt-3 rounded bg-red-100 px-3 py-2 text-sm text-red-700">{error}</p>}
      </form>

      <section className="rounded bg-white p-4 shadow">
        <p className="mb-3 text-sm text-slate-500">Total hits: {total}</p>
        <div className="overflow-x-auto">
          <table className="min-w-full text-left text-sm">
            <thead className="border-b bg-slate-50 text-slate-600">
              <tr>
                <th className="px-3 py-2">Timestamp</th>
                <th className="px-3 py-2">Index</th>
                <th className="px-3 py-2">Agent</th>
                <th className="px-3 py-2">Rule level</th>
                <th className="px-3 py-2">Message</th>
              </tr>
            </thead>
            <tbody>
              {logs.map((log) => (
                <tr key={log.id} className="border-b align-top">
                  <td className="px-3 py-2">{log['@timestamp'] || '-'}</td>
                  <td className="px-3 py-2">{log.index}</td>
                  <td className="px-3 py-2">{log.agent?.name || '-'}</td>
                  <td className="px-3 py-2">{log.rule?.level || '-'}</td>
                  <td className="px-3 py-2">{log.rule?.description || log.full_log || '-'}</td>
                </tr>
              ))}
              {logs.length === 0 && (
                <tr>
                  <td className="px-3 py-4 text-slate-500" colSpan={5}>
                    No logs found. Try a query or adjust filters.
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
