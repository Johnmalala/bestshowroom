import React, { useState, useEffect } from 'react'
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Toaster } from 'react-hot-toast'
import { supabase } from './lib/supabase'
import App from './App'
import { Setup } from './pages/Setup'

const queryClient = new QueryClient()

const Root: React.FC = () => {
  const [needsSetup, setNeedsSetup] = useState<boolean | null>(null)

  useEffect(() => {
    const checkSetup = async () => {
      try {
        const { data, error } = await supabase.rpc('has_users')
        if (error) throw error
        setNeedsSetup(!data)
      } catch (err) {
        console.error("Error checking for initial setup:", err)
        // Fallback to assuming setup is not needed if check fails
        setNeedsSetup(false)
      }
    }
    checkSetup()
  }, [])

  if (needsSetup === null) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-brand-light">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-accent"></div>
      </div>
    )
  }

  return (
    <QueryClientProvider client={queryClient}>
      <Toaster position="top-center" reverseOrder={false} />
      <Router>
        <Routes>
          {needsSetup ? (
            <>
              <Route path="/setup" element={<Setup />} />
              <Route path="*" element={<Navigate to="/setup" replace />} />
            </>
          ) : (
            // If setup is complete, App component handles all routes
            <Route path="/*" element={<App />} />
          )}
        </Routes>
      </Router>
    </QueryClientProvider>
  )
}

export default Root
