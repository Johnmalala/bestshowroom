import React, { useState, useEffect, useMemo } from 'react'
import { supabase, Car, Customer, BrokerCommission, Payment } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth'
import { formatKES } from '../utils/currency'
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts'
import { Download, Calendar } from 'lucide-react'
import { exportToCSV } from '../utils/export'
import toast from 'react-hot-toast'
import { DataTable } from '../components/ui/DataTable'
import { ColumnDef } from '@tanstack/react-table'
import { format } from 'date-fns'

interface ReportData {
  carsSold: any[]
  hirePurchaseSummary: any[]
  brokerCommissions: any[]
  paymentsHistory: any[]
  salesByMonth: any[]
  carStatusData: any[]
}

export const Reports: React.FC = () => {
  const { isOwner } = useAuth()
  const [reportData, setReportData] = useState<ReportData>({
    carsSold: [],
    hirePurchaseSummary: [],
    brokerCommissions: [],
    paymentsHistory: [],
    salesByMonth: [],
    carStatusData: []
  })
  const [loading, setLoading] = useState(true)
  const [dateRange, setDateRange] = useState({
    from: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0],
    to: new Date().toISOString().split('T')[0]
  })

  useEffect(() => {
    fetchReportData()
  }, [dateRange, isOwner])

  const fetchReportData = async () => {
    try {
      setLoading(true)

      const { data: carsSold } = await supabase
        .from('cars')
        .select(`*, broker:brokers(name), customer:customers(full_name)`)
        .eq('status', 'sold')
        .gte('updated_at', dateRange.from)
        .lte('updated_at', dateRange.to)

      const { data: hirePurchase } = await supabase
        .from('customers')
        .select(`*, car:cars(car_type, model_number, registration_number, purchase_price)`)
        .not('hire_purchase_start_date', 'is', null)

      let brokerCommissions: any[] = []
      if (isOwner) {
        const { data: commissions } = await supabase
          .from('broker_commissions')
          .select(`*, broker:brokers(name), car:cars(car_type, model_number, registration_number)`)
          .gte('created_at', dateRange.from)
          .lte('created_at', dateRange.to)
        brokerCommissions = commissions || []
      }

      const { data: payments } = await supabase
        .from('payments')
        .select(`*, customer:customers(full_name), car:cars(car_type, model_number), staff:staff_profiles(full_name)`)
        .gte('payment_date', dateRange.from)
        .lte('payment_date', dateRange.to)
        .order('payment_date', { ascending: false })

      const salesByMonth = payments?.reduce((acc: any[], payment: any) => {
        const month = new Date(payment.payment_date).toLocaleDateString('en-US', { year: 'numeric', month: 'short' })
        const existing = acc.find(item => item.month === month)
        if (existing) {
          existing.amount += payment.amount
        } else {
          acc.push({ month, amount: payment.amount })
        }
        return acc
      }, []) || []

      const { data: allCars } = await supabase.from('cars').select('id, status')
      const totalSold = allCars?.filter(c => c.status === 'sold').length || 0
      const totalAvailable = allCars?.filter(c => c.status === 'available').length || 0
      
      const carStatusData = [
        { name: 'Available', value: totalAvailable, color: '#3B82F6' },
        { name: 'Sold', value: totalSold, color: '#10B981' }
      ]

      setReportData({
        carsSold: carsSold || [],
        hirePurchaseSummary: hirePurchase || [],
        brokerCommissions,
        paymentsHistory: payments || [],
        salesByMonth,
        carStatusData
      })
    } catch (error) {
      console.error('Error fetching report data:', error)
      toast.error("Failed to load report data.")
    } finally {
      setLoading(false)
    }
  }

  const handleExport = (data: any[], filename: string) => {
    if (data.length === 0) {
      toast.error("No data available to export.");
      return;
    }
    exportToCSV(data, filename);
    toast.success(`${filename}.csv has been downloaded.`);
  }

  const carsSoldColumns = useMemo<ColumnDef<Car>[]>(() => [
    { header: 'Car', cell: ({ row }) => `${row.original.car_type} ${row.original.model_number}` },
    { accessorKey: 'registration_number', header: 'Reg No.' },
    { header: 'Sold To', cell: ({ row }) => (row.original as any).customer?.full_name || 'N/A' },
    { header: 'Price', cell: ({ row }) => formatKES(row.original.purchase_price) },
    { header: 'Broker', cell: ({ row }) => (row.original as any).broker?.name || 'N/A' },
    { header: 'Date Sold', cell: ({ row }) => format(new Date(row.original.updated_at), 'PP') },
  ], []);

  const hirePurchaseColumns = useMemo<ColumnDef<Customer>[]>(() => [
    { accessorKey: 'full_name', header: 'Customer' },
    { header: 'Car', cell: ({ row }) => `${(row.original as any).car?.car_type} ${(row.original as any).car?.model_number}` },
    { header: 'Total Price', cell: ({ row }) => formatKES((row.original as any).car?.purchase_price || 0) },
    { header: 'Paid', cell: ({ row }) => formatKES(row.original.deposit_paid) },
    { header: 'Balance', cell: ({ row }) => formatKES(row.original.remaining_balance) },
    { header: 'Start Date', cell: ({ row }) => row.original.hire_purchase_start_date ? format(new Date(row.original.hire_purchase_start_date), 'PP') : 'N/A' },
  ], []);

  const brokerCommissionsColumns = useMemo<ColumnDef<BrokerCommission>[]>(() => [
    { header: 'Broker', cell: ({ row }) => (row.original as any).broker?.name },
    { header: 'Car', cell: ({ row }) => `${(row.original as any).car?.car_type} ${(row.original as any).car?.registration_number}` },
    { header: 'Amount', cell: ({ row }) => formatKES(row.original.commission_amount) },
    { header: 'Status', cell: ({ row }) => row.original.is_paid ? 'Paid' : 'Pending' },
    { header: 'Paid Date', cell: ({ row }) => row.original.paid_date ? format(new Date(row.original.paid_date), 'PP') : 'N/A' },
  ], []);

  const paymentsHistoryColumns = useMemo<ColumnDef<Payment>[]>(() => [
    { header: 'Customer', cell: ({ row }) => (row.original as any).customer?.full_name },
    { header: 'Amount', cell: ({ row }) => formatKES(row.original.amount) },
    { header: 'Type', cell: ({ row }) => row.original.payment_type.replace(/_/g, ' ') },
    { header: 'Date', cell: ({ row }) => format(new Date(row.original.payment_date), 'PP') },
    { header: 'Received By', cell: ({ row }) => (row.original as any).staff?.full_name || 'N/A' },
  ], []);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
      </div>
    )
  }
  
  const reports = [
    { title: "Cars Sold Report", data: reportData.carsSold, columns: carsSoldColumns, filename: "cars-sold" },
    { title: "Hire Purchase Summary", data: reportData.hirePurchaseSummary, columns: hirePurchaseColumns, filename: "hire-purchase" },
    ...(isOwner ? [{ title: "Broker Commissions Report", data: reportData.brokerCommissions, columns: brokerCommissionsColumns, filename: "broker-commissions" }] : []),
    { title: "Payments History", data: reportData.paymentsHistory, columns: paymentsHistoryColumns, filename: "payments-history" }
  ];

  return (
    <div className="space-y-8">
      <header>
        <h1 className="text-3xl font-bold text-gray-900">Reports</h1>
        <p className="mt-2 text-sm text-gray-500">
          Comprehensive business analytics and reports.
        </p>
      </header>

      <div className="bg-white p-4 rounded-xl shadow-sm">
        <div className="flex flex-wrap items-center gap-4">
          <div className="flex items-center gap-2">
            <Calendar className="h-5 w-5 text-gray-500" />
            <span className="text-sm font-medium text-gray-700">Filter by Date Range:</span>
          </div>
          <input
            type="date"
            value={dateRange.from}
            onChange={(e) => setDateRange(prev => ({ ...prev, from: e.target.value }))}
            className="border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
          />
          <span className="text-gray-500">to</span>
          <input
            type="date"
            value={dateRange.to}
            onChange={(e) => setDateRange(prev => ({ ...prev, to: e.target.value }))}
            className="border-gray-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
          />
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <div className="bg-white p-6 rounded-xl shadow-sm">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Sales Over Time</h3>
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={reportData.salesByMonth}>
              <CartesianGrid strokeDasharray="3 3" vertical={false} />
              <XAxis dataKey="month" fontSize={12} tickLine={false} axisLine={false} />
              <YAxis fontSize={12} tickLine={false} axisLine={false} tickFormatter={(value) => formatKES(value)} />
              <Tooltip formatter={(value) => [formatKES(Number(value)), 'Sales']} contentStyle={{ background: 'white', border: '1px solid #e2e8f0', borderRadius: '0.5rem' }} />
              <Bar dataKey="amount" fill="#3B82F6" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div className="bg-white p-6 rounded-xl shadow-sm">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Inventory Status</h3>
          <ResponsiveContainer width="100%" height={300}>
            <PieChart>
              <Pie data={reportData.carStatusData} cx="50%" cy="50%" outerRadius={100} dataKey="value" label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}>
                {reportData.carStatusData.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.color} />
                ))}
              </Pie>
              <Tooltip formatter={(value, name) => [value, name]} />
              <Legend iconType="circle" />
            </PieChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="space-y-8">
        {reports.map(report => (
          <div key={report.title} className="bg-white shadow-sm rounded-xl p-4 sm:p-6">
            <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-4 gap-4">
              <h3 className="text-xl leading-6 font-semibold text-gray-900">{report.title}</h3>
              <button
                onClick={() => handleExport(report.data, `${report.filename}-report-${dateRange.to}`)}
                className="inline-flex items-center gap-2 px-3 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
              >
                <Download className="h-4 w-4" /> Export CSV
              </button>
            </div>
            {report.data.length > 0 ? (
              <DataTable columns={report.columns} data={report.data} />
            ) : (
              <p className="text-center text-gray-500 py-10">No data available for this report in the selected date range.</p>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}
