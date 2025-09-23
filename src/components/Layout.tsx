import React from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { 
  Car, 
  Users, 
  CreditCard, 
  BarChart3, 
  Settings, 
  LogOut, 
  Menu,
  X,
  LayoutDashboard,
  UserCheck,
  Building
} from 'lucide-react'

interface LayoutProps {
  children: React.ReactNode
}

export const Layout: React.FC<LayoutProps> = ({ children }) => {
  const { profile, signOut, isOwner, isManager } = useAuth()
  const location = useLocation()
  const navigate = useNavigate()
  const [sidebarOpen, setSidebarOpen] = React.useState(false)

  const handleSignOut = async () => {
    await signOut()
    navigate('/login')
  }

  const navigation = [
    { name: 'Dashboard', href: '/', icon: LayoutDashboard, allowed: true },
    { name: 'Cars', href: '/cars', icon: Car, allowed: true },
    { name: 'Customers', href: '/customers', icon: Users, allowed: true },
    { name: 'Payments', href: '/payments', icon: CreditCard, allowed: true },
    { name: 'Brokers', href: '/brokers', icon: UserCheck, allowed: isOwner },
    { name: 'Reports', href: '/reports', icon: BarChart3, allowed: isOwner || isManager },
    { name: 'Staff', href: '/staff', icon: Settings, allowed: isOwner },
  ].filter(item => item.allowed)

  const SidebarContent = () => (
    <>
      <div className="flex h-16 shrink-0 items-center px-4 gap-x-3">
        <Building className="h-8 w-8 text-brand-accent" />
        <h1 className="text-2xl font-bold text-white">AUTOHAUS</h1>
      </div>
      <nav className="flex flex-1 flex-col">
        <ul role="list" className="flex flex-1 flex-col gap-y-7">
          <li>
            <ul role="list" className="space-y-1">
              {navigation.map((item) => (
                <li key={item.name}>
                  <Link
                    to={item.href}
                    onClick={() => sidebarOpen && setSidebarOpen(false)}
                    className={`group flex gap-x-3 rounded-md p-2 mx-4 text-sm leading-6 font-semibold transition-colors duration-200 ${
                      location.pathname === item.href
                        ? 'bg-gray-800 text-white'
                        : 'text-gray-400 hover:text-white hover:bg-gray-800/50'
                    }`}
                  >
                    <item.icon className="h-6 w-6 shrink-0" />
                    {item.name}
                  </Link>
                </li>
              ))}
            </ul>
          </li>
          <li className="mt-auto border-t border-gray-700">
            <div className="flex items-center gap-x-4 px-6 py-4 text-sm font-semibold leading-6 text-white">
              <div className="h-10 w-10 rounded-full bg-gray-700 flex items-center justify-center">
                <span className="text-base font-medium text-gray-300">
                  {profile?.full_name?.charAt(0).toUpperCase()}
                </span>
              </div>
              <div className="flex-1">
                <div className="text-sm font-medium">{profile?.full_name}</div>
                <div className="text-xs text-gray-400 capitalize">{profile?.role}</div>
              </div>
              <button
                onClick={handleSignOut}
                className="text-gray-400 hover:text-white transition-colors duration-200"
                title="Sign out"
              >
                <LogOut className="h-6 w-6" />
              </button>
            </div>
          </li>
        </ul>
      </nav>
    </>
  )

  return (
    <div className="min-h-screen bg-brand-light flex">
      {/* Mobile sidebar */}
      <div className={`fixed inset-0 z-50 lg:hidden ${sidebarOpen ? 'block' : 'hidden'}`}>
        <div className="fixed inset-0 bg-gray-900/80" onClick={() => setSidebarOpen(false)} aria-hidden="true" />
        <div className="relative flex w-full max-w-xs flex-col bg-brand-dark">
          <div className="absolute top-0 right-0 -mr-12 pt-2">
            <button
              type="button"
              className="ml-1 flex h-10 w-10 items-center justify-center rounded-full focus:outline-none focus:ring-2 focus:ring-inset focus:ring-white"
              onClick={() => setSidebarOpen(false)}
            >
              <span className="sr-only">Close sidebar</span>
              <X className="h-6 w-6 text-white" />
            </button>
          </div>
          <div className="flex grow flex-col gap-y-5 overflow-y-auto pb-2">
            <SidebarContent />
          </div>
        </div>
      </div>

      {/* Desktop sidebar */}
      <div className="hidden lg:fixed lg:inset-y-0 lg:z-50 lg:flex lg:w-72 lg:flex-col">
        <div className="flex grow flex-col gap-y-5 overflow-y-auto bg-brand-dark">
          <SidebarContent />
        </div>
      </div>

      {/* Main content */}
      <div className="lg:pl-72 flex-1 flex flex-col">
        <div className="sticky top-0 z-40 flex h-16 shrink-0 items-center gap-x-4 border-b border-gray-200 bg-white px-4 shadow-sm sm:px-6 lg:hidden">
            <button type="button" className="-m-2.5 p-2.5 text-gray-700 lg:hidden" onClick={() => setSidebarOpen(true)}>
                <span className="sr-only">Open sidebar</span>
                <Menu className="h-6 w-6" />
            </button>
            <div className="flex-1 text-lg font-semibold leading-6 text-gray-900">AUTOHAUS</div>
        </div>
        <main className="flex-1 py-10">
          <div className="px-4 sm:px-6 lg:px-8">
            {children}
          </div>
        </main>
      </div>
    </div>
  )
}
