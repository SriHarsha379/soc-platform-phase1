import { useEffect, useState } from 'react';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import api from './api/client';
import Layout from './components/Layout';
import ProtectedRoute from './components/ProtectedRoute';
import DashboardPage from './pages/DashboardPage';
import LoginPage from './pages/LoginPage';
import LogsPage from './pages/LogsPage';
import IncidentsPage from './pages/IncidentsPage';

export default function App() {
  const token = localStorage.getItem('soc_token');
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(Boolean(token));

  useEffect(() => {
    if (!token) {
      return;
    }

    api
      .get('/api/auth/me')
      .then((response) => setUser(response.data))
      .catch(() => {
        localStorage.removeItem('soc_token');
        setUser(null);
      })
      .finally(() => setLoading(false));
  }, [token]);

  if (loading) {
    return <div className="flex min-h-screen items-center justify-center">Loading...</div>;
  }

  const isAuthenticated = Boolean(user);

  return (
    <BrowserRouter>
      <Routes>
        <Route
          path="/login"
          element={
            isAuthenticated ? (
              <Navigate to="/dashboard" replace />
            ) : (
              <LoginPage
                onLogin={(loggedInUser) => {
                  setUser(loggedInUser);
                }}
              />
            )
          }
        />
        <Route
          path="/dashboard"
          element={
            <ProtectedRoute isAuthenticated={isAuthenticated}>
              <Layout user={user}>
                <DashboardPage />
              </Layout>
            </ProtectedRoute>
          }
        />
        <Route
          path="/logs"
          element={
            <ProtectedRoute isAuthenticated={isAuthenticated}>
              <Layout user={user}>
                <LogsPage />
              </Layout>
            </ProtectedRoute>
          }
        />
        <Route
          path="/incidents"
          element={
            <ProtectedRoute isAuthenticated={isAuthenticated}>
              <Layout user={user}>
                <IncidentsPage />
              </Layout>
            </ProtectedRoute>
          }
        />
        <Route path="*" element={<Navigate to={isAuthenticated ? '/dashboard' : '/login'} replace />} />
      </Routes>
    </BrowserRouter>
  );
}
