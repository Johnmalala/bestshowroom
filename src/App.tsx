import React from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { useAuth } from './hooks/useAuth'
import { Layout } from './components/Layout'
import { AuthGuard } from './components/AuthGuard'
import { Login } from './pages/Login'
import { Dashboard } from './pages/Dashboard'

// Lazy load pages
const Cars = React.lazy(() => import('./pages/Cars').then(module => ({ default: module.Cars })))
const Customers = React.lazy(() => import('./pages/Customers').then(module => ({ default: module.Customers })))
const Payments = React.lazy(() => import('./pages/Payments').then(module => ({ default: module.Payments })))
const Brokers = React.lazy(() => import('./pages/Brokers').then(module => ({ default: module.Brokers })))
const Reports = React.lazy(() => import('./pages/Reports').then(module => ({ default: module.Reports })))
const Staff = React.lazy(() => import('./pages/Staff').then(module => ({ default: module.Staff })))

const PageLoader: React.FC = () => (
    <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-accent"></div>
    </div>
)

const ProtectedRoute: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { user, loading } = useAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-brand-light">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-accent"></div>
      </div>
    )
  }

  if (!user) {
    return <Navigate to="/login" replace />
  }

  return <Layout>{children}</Layout>
}

function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        path="/"
        element={
          <ProtectedRoute>
            <Dashboard />
          </ProtectedRoute>
        }
      />
      <Route
        path="/cars"
        element={
          <ProtectedRoute>
            <React.Suspense fallback={<PageLoader />}>
              <Cars />
            </React.Suspense>
          </ProtectedRoute>
        }
      />
      <Route
        path="/customers"
        element={
          <ProtectedRoute>
            <React.Suspense fallback={<PageLoader />}>
              <Customers />
            </React.Suspense>
          </ProtectedRoute>
        }
      />
      <Route
        path="/payments"
        element={
          <ProtectedRoute>
            <React.Suspense fallback={<PageLoader />}>
              <Payments />
            </React.Suspense>
          </ProtectedRoute>
        }
      />
      <Route
        path="/brokers"
        element={
          <ProtectedRoute>
            <AuthGuard requiredRole={['owner']}>
              <React.Suspense fallback={<PageLoader />}>
                <Brokers />
              </React.Suspense>
            </AuthGuard>
          </ProtectedRoute>
        }
      />
      <Route
        path="/reports"
        element={
          <ProtectedRoute>
            <AuthGuard requiredRole={['owner', 'manager']}>
              <React.Suspense fallback={<PageLoader />}>
                <Reports />
              </React.Suspense>
            </AuthGuard>
          </ProtectedRoute>
        }
      />
      <Route
        path="/staff"
        element={
          <ProtectedRoute>
            <AuthGuard requiredRole={['owner']}>
              <React.Suspense fallback={<PageLoader />}>
                <Staff />
              </React.Suspense>
            </AuthGuard>
          </ProtectedRoute>
        }
      />
      {/* Add a catch-all for any other routes */}
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

export default App
