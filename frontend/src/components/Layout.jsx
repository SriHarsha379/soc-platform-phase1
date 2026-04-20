import { Link, NavLink, useNavigate } from 'react-router-dom';

const navClass = ({ isActive }) =>
  `rounded px-3 py-2 text-sm ${isActive ? 'bg-slate-800 text-white' : 'text-slate-700 hover:bg-slate-200'}`;

export default function Layout({ user, children }) {
  const navigate = useNavigate();

  const logout = () => {
    localStorage.removeItem('soc_token');
    navigate('/login');
  };

  return (
    <div className="min-h-screen bg-slate-100">
      <header className="border-b bg-white">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
          <Link to="/dashboard" className="text-lg font-semibold text-slate-900">
            SOC Dashboard
          </Link>
          <nav className="flex items-center gap-2">
            <NavLink to="/dashboard" className={navClass}>
              Dashboard
            </NavLink>
            <NavLink to="/logs" className={navClass}>
              Logs
            </NavLink>
            <span className="ml-3 hidden rounded bg-slate-100 px-2 py-1 text-xs uppercase text-slate-600 md:inline">
              {user?.role || 'unknown'}
            </span>
            <button
              onClick={logout}
              className="ml-2 rounded bg-red-600 px-3 py-2 text-sm text-white hover:bg-red-700"
              type="button"
            >
              Logout
            </button>
          </nav>
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-4 py-6">{children}</main>
    </div>
  );
}
