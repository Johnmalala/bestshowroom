import React, { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth'
import { formatKES } from '../utils/currency'
import { Car, TrendingUp, DollarSign, Clock, ArrowUp, ArrowDown, Download } from 'lucide-react'
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, Legend } from 'recharts'
import { format } from 'date-fns'

interface DashboardStats {
  totalCars: number
  soldCars: number
  totalSales: number
  totalOutstanding: number
  salesByMonth: { month: string; sales: number }[]
  carStatusData: { name: string; value: number }[]
  recentPayments: any[]
}

interface StatCardProps {
  icon: React.ElementType;
  title: string;
  value: string;
  change?: number;
  iconColor: string;
}

const StatCard: React.FC<StatCardProps> = ({ icon: Icon, title, value, change, iconColor }) => {
  const isPositive = change && change >= 0;
  return (
    <div className="bg-white p-6 rounded-xl shadow-sm flex items-start justify-between">
      <div>
        <p className="text-sm font-medium text-gray-500">{title}</p>
        <p className="text-3xl font-bold text-gray-900 mt-2">{value}</p>
        {change !== undefined && (
          <div className="flex items-center mt-2 text-sm">
            {isPositive ? (
              <ArrowUp className="w-4 h-4 text-green-500" />
            ) : (
              <ArrowDown className="w-4 h-4 text-red-500" />
            )}
            <span className={`ml-1 font-semibold ${isPositive ? 'text-green-500' : 'text-red-500'}`}>
              {Math.abs(change)}%
            </span>
            <span className="ml-1 text-gray-500">vs last month</span>
          </div>
        )}
      </div>
      <div className={`p-3 rounded-lg bg-opacity-10 ${iconColor.replace('text-', 'bg-')}`}>
        <Icon className={`w-6 h-6 ${iconColor}`} />
      </div>
    </div>
  );
};

export const Dashboard: React.FC = () => {
  const { profile } = useAuth()
  const [stats, setStats] = useState<DashboardStats | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetchDashboardData()
  }, [])

  const fetchDashboardData = async () => {
    try {
      setLoading(true)
      const { data: cars } = await supabase.from('cars').select('id, status, purchase_price')
      const { data: customers } = await supabase.from('customers').select('remaining_balance')
      const { data: payments } = await supabase.from('payments').select('id, amount, payment_date, payment_type, customer:customers(full_name)').order('created_at', { ascending: false }).limit(5)

      const totalCars = cars?.length || 0
      const soldCars = cars?.filter(c => c.status === 'sold').length || 0
      const availableCars = totalCars - soldCars
      
      const totalSales = cars?.filter(c => c.status === 'sold').reduce((sum, car) => sum + car.purchase_price, 0) || 0
      const totalOutstanding = customers?.reduce((sum, cust) => sum + cust.remaining_balance, 0) || 0

      const salesByMonth = (await supabase.from('payments').select('amount, payment_date')).data?.reduce((acc: any, p: any) => {
        const month = format(new Date(p.payment_date), 'MMM');
        acc[month] = (acc[month] || 0) + p.amount;
        return acc;
      }, {}) || {};
      
      const monthOrder = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
      const formattedSales = monthOrder.map(m => ({ month: m, sales: salesByMonth[m] || 0 }));

      setStats({
        totalCars,
        soldCars,
        totalSales,
        totalOutstanding,
        salesByMonth: formattedSales,
        carStatusData: [
          { name: 'Available', value: availableCars },
          { name: 'Sold', value: soldCars },
        ],
        recentPayments: payments || []
      })
    } catch (error) {
      console.error('Error fetching dashboard data:', error)
    } finally {
      setLoading(false)
    }
  }

  if (loading || !stats) {
    return (
      <div className="flex items-center justify-center h-96">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-brand-accent"></div>
      </div>
    )
  }

  const PIE_COLORS = ['#3B82F6', '#10B981'];

  return (
    <div className="space-y-8">
      <header className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Welcome back, {profile?.full_name?.split(' ')[0]}!</h1>
          <p className="mt-2 text-gray-600">Here’s a summary of your showroom's performance.</p>
        </div>
        <button
          className="inline-flex items-center justify-center gap-2 px-4 py-2 border border-transparent rounded-lg shadow-sm text-sm font-medium text-white bg-brand-accent hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors"
        >
          <Download className="h-4 w-4" />
          Download Report
        </button>
      </header>

      <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard icon={DollarSign} title="Total Revenue" value={formatKES(stats.totalSales)} change={5.2} iconColor="text-green-500" />
        <StatCard icon={TrendingUp} title="Cars Sold" value={stats.soldCars.toString()} change={12.5} iconColor="text-blue-500" />
        <StatCard icon={Clock} title="Pending Balance" value={formatKES(stats.totalOutstanding)} change={-2.1} iconColor="text-yellow-500" />
        <StatCard icon={Car} title="Total Cars" value={stats.totalCars.toString()} iconColor="text-purple-500" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-2 bg-white p-6 rounded-xl shadow-sm">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Monthly Sales</h3>
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={stats.salesByMonth} margin={{ top: 5, right: 20, left: 30, bottom: 5 }}>
              <CartesianGrid strokeDasharray="3 3" vertical={false} />
              <XAxis dataKey="month" fontSize={12} tickLine={false} axisLine={false} />
              <YAxis fontSize={12} tickLine={false} axisLine={false} tickFormatter={(value) => `${formatKES(Number(value) / 1000)}k`} />
              <Tooltip cursor={{ fill: 'rgba(239, 246, 255, 0.7)' }} contentStyle={{ background: 'white', border: '1px solid #e2e8f0', borderRadius: '0.5rem' }} formatter={(value) => [formatKES(Number(value)), 'Sales']} />
              <Bar dataKey="sales" fill="#3B82F6" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div className="bg-white p-6 rounded-xl shadow-sm">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Inventory Status</h3>
          <ResponsiveContainer width="100%" height={300}>
            <PieChart>
              <Pie data={stats.carStatusData} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={60} outerRadius={85} paddingAngle={5} labelLine={false}>
                {stats.carStatusData.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={PIE_COLORS[index % PIE_COLORS.length]} className="focus:outline-none" />
                ))}
              </Pie>
              <Tooltip formatter={(value) => [value, 'Cars']} />
              <Legend iconType="circle" iconSize={10} />
            </PieChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="bg-white shadow-sm rounded-xl">
        <div className="px-4 py-5 sm:p-6">
          <h3 className="text-lg leading-6 font-semibold text-gray-900 mb-4">
            Recent Payments
          </h3>
          <div className="overflow-x-auto">
            <table className="min-w-full">
              <thead className="border-b border-gray-200">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Customer</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Amount</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Type</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Date</th>
                </tr>
              </thead>
              <tbody>
                {stats.recentPayments.map((payment, index) => (
                  <tr key={payment.id} className={index % 2 === 0 ? 'bg-white' : 'bg-gray-50'}>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{payment.customer?.full_name}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-700">{formatKES(payment.amount)}</td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full capitalize ${
                        payment.payment_type === 'full_purchase' ? 'bg-green-100 text-green-800' :
                        payment.payment_type === 'hire_purchase_deposit' ? 'bg-blue-100 text-blue-800' :
                        'bg-yellow-100 text-yellow-800'
                      }`}>
                        {payment.payment_type.replace(/_/g, ' ')}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{format(new Date(payment.payment_date), 'PP')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  )
}
