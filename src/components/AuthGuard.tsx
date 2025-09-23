import React from 'react'
import { useAuth } from '../hooks/useAuth'
import { UserRole } from '../lib/supabase'

interface AuthGuardProps {
  children: React.ReactNode
  requiredRole?: UserRole[]
  fallback?: React.ReactNode
}

export const AuthGuard: React.FC<AuthGuardProps> = ({ 
  children, 
  requiredRole = [], 
  fallback 
}) => {
  const { profile } = useAuth()

  if (!profile) {
    return fallback || <div className="text-center py-4">Access denied</div>
  }

  if (requiredRole.length > 0 && !requiredRole.includes(profile.role)) {
    return fallback || <div className="text-center py-4">Insufficient permissions</div>
  }

  return <>{children}</>
}
