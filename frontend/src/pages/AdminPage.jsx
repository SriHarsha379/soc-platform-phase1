import { useEffect, useState } from 'react';
import api from '../api/client';

// ── Small reusable components ──────────────────────────────────────────────────

function Field({ label, id, ...props }) {
  return (
    <div>
      <label htmlFor={id} className="mb-1 block text-xs font-medium text-slate-700">
        {label}
      </label>
      <input
        id={id}
        className="w-full rounded border border-slate-300 px-2 py-1.5 text-sm outline-none focus:border-blue-500"
        {...props}
      />
    </div>
  );
}

function SectionHeader({ title, subtitle }) {
  return (
    <div className="border-b px-4 py-3">
      <h2 className="font-semibold text-slate-900">{title}</h2>
      {subtitle && <p className="mt-0.5 text-xs text-slate-500">{subtitle}</p>}
    </div>
  );
}

// ── Tenant list + create tenant ───────────────────────────────────────────────

function TenantsSection({ isSuperAdmin }) {
  const [tenants, setTenants] = useState([]);
  const [loading, setLoading] = useState(isSuperAdmin);
  const [error, setError] = useState('');
  const [form, setForm] = useState({ name: '', slug: '', adminEmail: '', adminPassword: '' });
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState('');
  const [selectedTenant, setSelectedTenant] = useState(null);

  useEffect(() => {
    if (!isSuperAdmin) return;
    api
      .get('/api/tenants')
      .then((resp) => setTenants(resp.data))
      .catch((err) => setError(err.response?.data?.error || 'Failed to load tenants'))
      .finally(() => setLoading(false));
  }, [isSuperAdmin]);

  const handleFormChange = (e) => setForm((prev) => ({ ...prev, [e.target.name]: e.target.value }));

  const handleCreate = async (e) => {
    e.preventDefault();
    setCreateError('');
    setCreating(true);
    try {
      const resp = await api.post('/api/tenants', form);
      setTenants((prev) => [...prev, resp.data]);
      setForm({ name: '', slug: '', adminEmail: '', adminPassword: '' });
    } catch (err) {
      setCreateError(err.response?.data?.error || 'Failed to create tenant');
    } finally {
      setCreating(false);
    }
  };

  if (!isSuperAdmin) return null;

  return (
    <>
      {/* Tenant list */}
      <section className="rounded bg-white shadow">
        <SectionHeader
          title="Tenants"
          subtitle="All tenants registered on this SOC platform."
        />
        {loading ? (
          <p className="p-6 text-sm text-slate-500">Loading…</p>
        ) : error ? (
          <p className="p-4 text-sm text-red-700">{error}</p>
        ) : (
          <table className="min-w-full text-left text-sm">
            <thead className="border-b bg-slate-50 text-slate-600">
              <tr>
                <th className="px-3 py-2">ID</th>
                <th className="px-3 py-2">Name</th>
                <th className="px-3 py-2">Slug</th>
                <th className="px-3 py-2 text-right">Users</th>
                <th className="px-3 py-2 text-right">Alerts</th>
                <th className="px-3 py-2 text-right">Incidents</th>
                <th className="px-3 py-2">Created</th>
                <th className="px-3 py-2">Manage</th>
              </tr>
            </thead>
            <tbody>
              {tenants.map((t) => (
                <tr key={t.id} className="border-b hover:bg-slate-50">
                  <td className="px-3 py-2 text-slate-500">{t.id}</td>
                  <td className="px-3 py-2 font-medium text-slate-900">{t.name}</td>
                  <td className="px-3 py-2 font-mono text-xs">{t.slug}</td>
                  <td className="px-3 py-2 text-right">{t._count?.users ?? '—'}</td>
                  <td className="px-3 py-2 text-right">{t._count?.alerts ?? '—'}</td>
                  <td className="px-3 py-2 text-right">{t._count?.incidents ?? '—'}</td>
                  <td className="px-3 py-2 text-xs text-slate-500">
                    {new Date(t.createdAt).toLocaleDateString()}
                  </td>
                  <td className="px-3 py-2">
                    <button
                      type="button"
                      onClick={() => setSelectedTenant(selectedTenant?.id === t.id ? null : t)}
                      className="rounded bg-indigo-50 px-2 py-0.5 text-xs text-indigo-700 hover:bg-indigo-100"
                    >
                      {selectedTenant?.id === t.id ? 'Hide users' : 'Users'}
                    </button>
                  </td>
                </tr>
              ))}
              {tenants.length === 0 && (
                <tr>
                  <td className="px-3 py-6 text-slate-500" colSpan={8}>
                    No tenants found.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        )}
      </section>

      {/* Per-tenant user management panel (inline) */}
      {selectedTenant && (
        <UserManagementSection tenantId={selectedTenant.id} tenantName={selectedTenant.name} />
      )}

      {/* Create tenant */}
      <section className="rounded bg-white shadow">
        <SectionHeader title="Create New Tenant" subtitle="Provision a new isolated SOC environment." />
        <form onSubmit={handleCreate} className="space-y-3 p-4">
          <div className="grid gap-3 md:grid-cols-2">
            <Field
              label="Tenant name"
              id="t-name"
              name="name"
              value={form.name}
              onChange={handleFormChange}
              placeholder="Acme Corp"
              required
            />
            <Field
              label="Slug (URL-safe)"
              id="t-slug"
              name="slug"
              value={form.slug}
              onChange={handleFormChange}
              placeholder="acme"
              pattern="[a-z0-9-]+"
              title="Lowercase letters, numbers, and hyphens only"
              required
            />
            <Field
              label="Initial admin email (optional)"
              id="t-email"
              name="adminEmail"
              type="email"
              value={form.adminEmail}
              onChange={handleFormChange}
              placeholder="admin@acme.com"
            />
            <Field
              label="Initial admin password (optional)"
              id="t-pass"
              name="adminPassword"
              type="password"
              value={form.adminPassword}
              onChange={handleFormChange}
              placeholder="••••••••"
            />
          </div>
          {createError && (
            <p className="rounded bg-red-100 px-3 py-2 text-sm text-red-700">{createError}</p>
          )}
          <button
            type="submit"
            disabled={creating}
            className="rounded bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
          >
            {creating ? 'Creating…' : 'Create Tenant'}
          </button>
        </form>
      </section>
    </>
  );
}

// ── Per-tenant user management ────────────────────────────────────────────────

function UserManagementSection({ tenantId, tenantName }) {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [form, setForm] = useState({ email: '', password: '', role: 'analyst' });
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState('');

  useEffect(() => {
    api
      .get(`/api/tenants/${tenantId}/users`)
      .then((resp) => setUsers(resp.data))
      .catch((err) => setError(err.response?.data?.error || 'Failed to load users'))
      .finally(() => setLoading(false));
  }, [tenantId]);

  const handleFormChange = (e) =>
    setForm((prev) => ({ ...prev, [e.target.name]: e.target.value }));

  const handleCreate = async (e) => {
    e.preventDefault();
    setCreateError('');
    setCreating(true);
    try {
      const resp = await api.post(`/api/tenants/${tenantId}/users`, form);
      setUsers((prev) => [...prev, resp.data]);
      setForm({ email: '', password: '', role: 'analyst' });
    } catch (err) {
      setCreateError(err.response?.data?.error || 'Failed to create user');
    } finally {
      setCreating(false);
    }
  };

  const handleDelete = async (userId) => {
    if (!window.confirm('Remove this user from the tenant?')) return;
    try {
      await api.delete(`/api/tenants/${tenantId}/users/${userId}`);
      setUsers((prev) => prev.filter((u) => u.id !== userId));
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to delete user');
    }
  };

  return (
    <section className="rounded border border-indigo-200 bg-indigo-50 shadow">
      <SectionHeader
        title={`Users – ${tenantName}`}
        subtitle="Manage users for this tenant."
      />
      <div className="p-4">
        {loading ? (
          <p className="text-sm text-slate-500">Loading users…</p>
        ) : error ? (
          <p className="text-sm text-red-700">{error}</p>
        ) : (
          <table className="mb-4 min-w-full text-left text-sm">
            <thead className="border-b bg-white text-slate-600">
              <tr>
                <th className="px-3 py-2">Email</th>
                <th className="px-3 py-2">Role</th>
                <th className="px-3 py-2">Created</th>
                <th className="px-3 py-2">Actions</th>
              </tr>
            </thead>
            <tbody>
              {users.map((u) => (
                <tr key={u.id} className="border-b bg-white hover:bg-slate-50">
                  <td className="px-3 py-2">{u.email}</td>
                  <td className="px-3 py-2 capitalize">{u.role}</td>
                  <td className="px-3 py-2 text-xs text-slate-500">
                    {new Date(u.createdAt).toLocaleDateString()}
                  </td>
                  <td className="px-3 py-2">
                    <button
                      type="button"
                      onClick={() => handleDelete(u.id)}
                      className="rounded bg-red-100 px-2 py-0.5 text-xs text-red-700 hover:bg-red-200"
                    >
                      Remove
                    </button>
                  </td>
                </tr>
              ))}
              {users.length === 0 && (
                <tr>
                  <td className="px-3 py-4 text-slate-500" colSpan={4}>
                    No users yet.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        )}

        {/* Add user form */}
        <form onSubmit={handleCreate} className="space-y-3 rounded border border-slate-200 bg-white p-3">
          <p className="text-xs font-semibold uppercase tracking-wide text-slate-600">Add User</p>
          <div className="grid gap-3 md:grid-cols-3">
            <Field
              label="Email"
              id={`u-email-${tenantId}`}
              name="email"
              type="email"
              value={form.email}
              onChange={handleFormChange}
              placeholder="user@example.com"
              required
            />
            <Field
              label="Password"
              id={`u-pass-${tenantId}`}
              name="password"
              type="password"
              value={form.password}
              onChange={handleFormChange}
              placeholder="••••••••"
              required
            />
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-700" htmlFor={`u-role-${tenantId}`}>
                Role
              </label>
              <select
                id={`u-role-${tenantId}`}
                name="role"
                value={form.role}
                onChange={handleFormChange}
                className="w-full rounded border border-slate-300 px-2 py-1.5 text-sm outline-none focus:border-blue-500"
              >
                <option value="analyst">Analyst</option>
                <option value="admin">Admin</option>
              </select>
            </div>
          </div>
          {createError && (
            <p className="rounded bg-red-100 px-3 py-2 text-sm text-red-700">{createError}</p>
          )}
          <button
            type="submit"
            disabled={creating}
            className="rounded bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-60"
          >
            {creating ? 'Adding…' : 'Add User'}
          </button>
        </form>
      </div>
    </section>
  );
}

// ── Main AdminPage ────────────────────────────────────────────────────────────

export default function AdminPage({ user }) {
  const isSuperAdmin = user?.role === 'super_admin';
  const isAdmin = user?.role === 'admin';

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-slate-900">Administration</h1>
        <span className="rounded bg-slate-200 px-3 py-1 text-xs font-semibold uppercase text-slate-600">
          {user?.role}
        </span>
      </div>

      <TenantsSection isSuperAdmin={isSuperAdmin} />

      {/* Tenant admin: manage their own tenant's users */}
      {isAdmin && !isSuperAdmin && (
        <UserManagementSection tenantId={user.tenantId} tenantName={user.tenantName || 'My Tenant'} />
      )}

      {!isSuperAdmin && !isAdmin && (
        <p className="rounded bg-yellow-50 px-4 py-3 text-sm text-yellow-800">
          You do not have admin privileges.
        </p>
      )}
    </div>
  );
}
