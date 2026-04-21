import { useEffect, useState } from 'react';
import api from '../api/client';

const STATUS_CLASSES = {
  success: 'bg-green-100 text-green-800',
  simulated: 'bg-blue-100 text-blue-800',
  partial: 'bg-yellow-100 text-yellow-800',
  error: 'bg-red-100 text-red-800',
  skipped: 'bg-slate-100 text-slate-600',
};

function StatusBadge({ status }) {
  const cls = STATUS_CLASSES[status?.toLowerCase()] || 'bg-slate-100 text-slate-600';
  return (
    <span className={`rounded px-2 py-0.5 text-xs font-semibold capitalize ${cls}`}>{status}</span>
  );
}

function EnabledBadge({ enabled }) {
  return enabled ? (
    <span className="rounded bg-green-100 px-2 py-0.5 text-xs font-semibold text-green-800">
      Enabled
    </span>
  ) : (
    <span className="rounded bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-500">
      Disabled
    </span>
  );
}

export default function PlaybooksPage() {
  const [playbooks, setPlaybooks] = useState([]);
  const [executions, setExecutions] = useState([]);
  const [soarStatus, setSoarStatus] = useState(null);
  const [loadingPlaybooks, setLoadingPlaybooks] = useState(true);
  const [loadingExec, setLoadingExec] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    const load = async () => {
      try {
        const [healthRes, pbRes, execRes] = await Promise.allSettled([
          api.get('/api/soar/health'),
          api.get('/api/soar/playbooks'),
          api.get('/api/soar/executions'),
        ]);

        if (healthRes.status === 'fulfilled') {
          setSoarStatus(healthRes.value.data);
        }
        if (pbRes.status === 'fulfilled') {
          setPlaybooks(pbRes.value.data);
        } else {
          setError('Could not load playbooks – SOAR service may be unavailable.');
        }
        if (execRes.status === 'fulfilled') {
          setExecutions(execRes.value.data);
        }
      } catch {
        setError('Failed to load SOAR data.');
      } finally {
        setLoadingPlaybooks(false);
        setLoadingExec(false);
      }
    };
    load();
  }, []);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-slate-900">SOAR Playbooks</h1>
        {soarStatus && (
          <span
            className={`rounded px-3 py-1 text-xs font-semibold ${
              soarStatus.soarService === 'ok'
                ? 'bg-green-100 text-green-800'
                : 'bg-red-100 text-red-800'
            }`}
          >
            SOAR: {soarStatus.soarService}
          </span>
        )}
      </div>

      {error && <p className="rounded bg-red-100 px-4 py-2 text-sm text-red-700">{error}</p>}

      {/* Playbook list */}
      <section className="rounded bg-white shadow">
        <div className="border-b px-4 py-3">
          <h2 className="font-semibold text-slate-900">Playbook Definitions</h2>
          <p className="mt-0.5 text-xs text-slate-500">
            JSON-based automated response workflows. Triggered automatically when incidents are
            detected.
          </p>
        </div>
        {loadingPlaybooks ? (
          <p className="p-6 text-sm text-slate-500">Loading playbooks…</p>
        ) : (
          <div className="divide-y">
            {playbooks.map((pb) => (
              <div key={pb.id} className="px-4 py-4">
                <div className="flex flex-wrap items-start gap-2">
                  <span className="font-medium text-slate-900">{pb.name}</span>
                  <EnabledBadge enabled={pb.enabled} />
                  <span className="rounded bg-indigo-50 px-2 py-0.5 text-xs text-indigo-700">
                    {pb.trigger?.rule_type ?? 'any'}
                  </span>
                  <span className="rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-600">
                    min: {pb.trigger?.min_severity ?? 'low'}
                  </span>
                </div>
                <p className="mt-1 text-sm text-slate-500">{pb.description}</p>
                <div className="mt-2 flex flex-wrap gap-2">
                  {(pb.actions || []).map((action, i) => (
                    <span
                      key={i}
                      className="rounded bg-slate-100 px-2 py-0.5 text-xs text-slate-700"
                    >
                      {action.type}
                    </span>
                  ))}
                </div>
                {pb.conditions?.length > 0 && (
                  <p className="mt-1 text-xs text-slate-400">
                    Conditions:{' '}
                    {pb.conditions
                      .map((c) => `${c.field} ${c.operator} ${c.value}`)
                      .join(' AND ')}
                  </p>
                )}
              </div>
            ))}
            {playbooks.length === 0 && (
              <p className="px-4 py-6 text-sm text-slate-500">No playbooks found.</p>
            )}
          </div>
        )}
      </section>

      {/* Execution audit log */}
      <section className="rounded bg-white shadow">
        <div className="border-b px-4 py-3">
          <h2 className="font-semibold text-slate-900">Execution Audit Log</h2>
          <p className="mt-0.5 text-xs text-slate-500">
            Record of every automated action taken by the SOAR engine.
          </p>
        </div>
        {loadingExec ? (
          <p className="p-6 text-sm text-slate-500">Loading executions…</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-left text-sm">
              <thead className="border-b bg-slate-50 text-slate-600">
                <tr>
                  <th className="px-3 py-2">Playbook</th>
                  <th className="px-3 py-2">Incident</th>
                  <th className="px-3 py-2">Rule</th>
                  <th className="px-3 py-2">Severity</th>
                  <th className="px-3 py-2">Source IP</th>
                  <th className="px-3 py-2">Actions</th>
                  <th className="px-3 py-2">Status</th>
                  <th className="px-3 py-2">Triggered At</th>
                </tr>
              </thead>
              <tbody>
                {executions.map((ex) => (
                  <tr key={ex.id} className="border-b align-top hover:bg-slate-50">
                    <td className="px-3 py-2 font-medium text-slate-900">{ex.playbook_name}</td>
                    <td className="px-3 py-2 text-slate-500">#{ex.incident_id ?? '—'}</td>
                    <td className="px-3 py-2 text-slate-600">
                      {ex.rule_type?.replace('_', ' ') ?? '—'}
                    </td>
                    <td className="px-3 py-2 capitalize text-slate-600">{ex.severity ?? '—'}</td>
                    <td className="px-3 py-2 font-mono text-xs">{ex.source_ip ?? '—'}</td>
                    <td className="px-3 py-2">
                      <div className="flex flex-wrap gap-1">
                        {(ex.actions_taken || []).map((a, i) => (
                          <span
                            key={i}
                            className={`rounded px-1.5 py-0.5 text-xs ${
                              STATUS_CLASSES[a.status] || 'bg-slate-100 text-slate-600'
                            }`}
                            title={a.note || a.error || ''}
                          >
                            {a.action_type}
                          </span>
                        ))}
                      </div>
                    </td>
                    <td className="px-3 py-2">
                      <StatusBadge status={ex.status} />
                    </td>
                    <td className="px-3 py-2 text-xs text-slate-500">
                      {new Date(ex.triggered_at).toLocaleString()}
                    </td>
                  </tr>
                ))}
                {executions.length === 0 && (
                  <tr>
                    <td className="px-3 py-6 text-slate-500" colSpan={8}>
                      No executions yet. Playbooks fire automatically when incidents are detected.
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
