import React, { useState, useEffect, useMemo } from 'react'
import { supabase, Customer, Car, StaffProfile } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth'
import { formatKES } from '../utils/currency'
import { Plus, Edit, User } from 'lucide-react'
import { Modal } from '../components/ui/Modal'
import { DataTable } from '../components/ui/DataTable'
import { ColumnDef } from '@tanstack/react-table'
import toast from 'react-hot-toast'

export const Customers: React.FC = () => {
  const { isOwner, isManager, profile } = useAuth()
  const [customers, setCustomers] = useState<Customer[]>([])
  const [cars, setCars] = useState<Car[]>([])
  const [staff, setStaff] = useState<StaffProfile[]>([])
  const [loading, setLoading] = useState(true)
  const [showModal, setShowModal] = useState(false)
  const [editingCustomer, setEditingCustomer] = useState<Customer | null>(null)

  const [formData, setFormData] = useState({
    full_name: '',
    phone_number: '',
    email: '',
    car_id: '',
    deposit_paid: '',
    remaining_balance: '',
    hire_purchase_start_date: '',
    hire_purchase_end_date: '',
    served_by: profile?.id || ''
  })

  useEffect(() => {
    fetchCustomers()
    fetchCars()
    fetchStaff()
  }, [])

  const fetchCustomers = async () => {
    try {
      setLoading(true)
      const { data, error } = await supabase
        .from('customers')
        .select(`*, car:cars(*), staff:staff_profiles(*)`)
        .order('created_at', { ascending: false })

      if (error) throw error
      setCustomers(data || [])
    } catch (error) {
      console.error('Error fetching customers:', error)
      toast.error('Failed to fetch customers.')
    } finally {
      setLoading(false)
    }
  }

  const fetchCars = async () => {
    try {
      const { data, error } = await supabase.from('cars').select('*').eq('status', 'available').order('car_type')
      if (error) throw error
      setCars(data || [])
    } catch (error) {
      console.error('Error fetching cars:', error)
    }
  }

  const fetchStaff = async () => {
    try {
      const { data, error } = await supabase.from('staff_profiles').select('*').order('full_name')
      if (error) throw error
      setStaff(data || [])
    } catch (error) {
      console.error('Error fetching staff:', error)
    }
  }

  const handleCloseModal = () => {
    setShowModal(false)
    setEditingCustomer(null)
    resetForm()
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const toastId = toast.loading(editingCustomer ? 'Updating customer...' : 'Adding customer...');
    
    try {
      const customerData = {
        full_name: formData.full_name,
        phone_number: formData.phone_number,
        email: formData.email || null,
        car_id: formData.car_id || null,
        deposit_paid: formData.deposit_paid ? parseFloat(formData.deposit_paid) : 0,
        remaining_balance: formData.remaining_balance ? parseFloat(formData.remaining_balance) : 0,
        hire_purchase_start_date: formData.hire_purchase_start_date || null,
        hire_purchase_end_date: formData.hire_purchase_end_date || null,
        served_by: formData.served_by || profile?.id
      }

      if (editingCustomer) {
        const { error } = await supabase.from('customers').update(customerData).eq('id', editingCustomer.id)
        if (error) throw error
        toast.success('Customer updated successfully!', { id: toastId });
      } else {
        const { error } = await supabase.from('customers').insert([customerData])
        if (error) throw error
        toast.success('Customer added successfully!', { id: toastId });
      }

      handleCloseModal()
      fetchCustomers()
    } catch (error: any) {
      toast.error(`Error: ${error.message}`, { id: toastId });
    }
  }

  const resetForm = () => {
    setFormData({
      full_name: '',
      phone_number: '',
      email: '',
      car_id: '',
      deposit_paid: '',
      remaining_balance: '',
      hire_purchase_start_date: '',
      hire_purchase_end_date: '',
      served_by: profile?.id || ''
    })
  }

  const handleEdit = (customer: Customer) => {
    if (!isOwner && !isManager) return
    
    setEditingCustomer(customer)
    setFormData({
      full_name: customer.full_name,
      phone_number: customer.phone_number,
      email: customer.email || '',
      car_id: customer.car_id || '',
      deposit_paid: customer.deposit_paid.toString(),
      remaining_balance: customer.remaining_balance.toString(),
      hire_purchase_start_date: customer.hire_purchase_start_date ? new Date(customer.hire_purchase_start_date).toISOString().split('T')[0] : '',
      hire_purchase_end_date: customer.hire_purchase_end_date ? new Date(customer.hire_purchase_end_date).toISOString().split('T')[0] : '',
      served_by: customer.served_by || ''
    })
    setShowModal(true)
  }

  const columns = useMemo<ColumnDef<Customer>[]>(() => [
    {
      accessorKey: 'full_name',
      header: 'Customer',
      cell: ({ row }) => (
        <div className="flex items-center">
          <div className="h-10 w-10 rounded-full bg-gray-100 flex items-center justify-center"><User className="h-6 w-6 text-gray-400" /></div>
          <div className="ml-4">
            <div className="text-sm font-medium text-gray-900">{row.original.full_name}</div>
            <div className="text-sm text-gray-500">{row.original.phone_number}</div>
          </div>
        </div>
      )
    },
    {
      accessorKey: 'car.car_type',
      header: 'Car Purchased',
      cell: ({ row }) => (
        row.original.car ? (
          <div className="text-sm text-gray-900">
            <div>{row.original.car.car_type} - {row.original.car.model_number}</div>
            <div className="text-gray-500">{row.original.car.registration_number}</div>
          </div>
        ) : <span className="text-sm text-gray-500">No car assigned</span>
      )
    },
    {
      accessorKey: 'remaining_balance',
      header: 'Payment Details',
      cell: ({ row }) => (
        <div className="text-sm text-gray-900">
          <div>Paid: {formatKES(row.original.deposit_paid)}</div>
          <div className="font-medium text-red-600">Balance: {formatKES(row.original.remaining_balance)}</div>
        </div>
      )
    },
    {
      accessorKey: 'staff.full_name',
      header: 'Served By',
      cell: ({ row }) => <div className="text-sm text-gray-500">{row.original.staff?.full_name || 'N/A'}</div>
    },
    {
      id: 'actions',
      header: 'Actions',
      cell: ({ row }) => (
        <div className="flex space-x-2">
          {(isOwner || isManager) && <button onClick={() => handleEdit(row.original)} className="text-indigo-600 hover:text-indigo-900 p-1"><Edit className="h-4 w-4" /></button>}
        </div>
      )
    }
  ], [isOwner, isManager])

  if (loading) {
    return <div className="flex items-center justify-center h-64"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div></div>
  }

  return (
    <div className="space-y-6">
      <div className="sm:flex sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Customers</h1>
          <p className="mt-1 text-sm text-gray-500">Manage customer records and purchases</p>
        </div>
        <div className="mt-4 sm:mt-0">
          <button onClick={() => setShowModal(true)} className="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
            <Plus className="h-4 w-4 mr-2" /> Add Customer
          </button>
        </div>
      </div>

      <DataTable columns={columns} data={customers} />

      <Modal isOpen={showModal} onClose={handleCloseModal} title={editingCustomer ? 'Edit Customer' : 'Add New Customer'} size="2xl">
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700">Full Name</label>
              <input type="text" required className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.full_name} onChange={(e) => setFormData(prev => ({ ...prev, full_name: e.target.value }))} />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Phone Number</label>
              <input type="tel" required className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.phone_number} onChange={(e) => setFormData(prev => ({ ...prev, phone_number: e.target.value }))} />
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700">Email (Optional)</label>
            <input type="email" className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.email} onChange={(e) => setFormData(prev => ({ ...prev, email: e.target.value }))} />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700">Car Purchased</label>
            <select className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.car_id} onChange={(e) => setFormData(prev => ({ ...prev, car_id: e.target.value }))}>
              <option value="">Select a car</option>
              {cars.map((car) => <option key={car.id} value={car.id}>{car.car_type} - {car.model_number} ({car.registration_number})</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700">Deposit Paid (KES)</label>
              <input type="number" step="0.01" className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.deposit_paid} onChange={(e) => setFormData(prev => ({ ...prev, deposit_paid: e.target.value }))} />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Remaining Balance (KES)</label>
              <input type="number" step="0.01" className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.remaining_balance} onChange={(e) => setFormData(prev => ({ ...prev, remaining_balance: e.target.value }))} />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700">Hire Purchase Start Date</label>
              <input type="date" className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.hire_purchase_start_date} onChange={(e) => setFormData(prev => ({ ...prev, hire_purchase_start_date: e.target.value }))} />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Hire Purchase End Date</label>
              <input type="date" className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.hire_purchase_end_date} onChange={(e) => setFormData(prev => ({ ...prev, hire_purchase_end_date: e.target.value }))} />
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700">Served By</label>
            <select className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.served_by} onChange={(e) => setFormData(prev => ({ ...prev, served_by: e.target.value }))}>
              <option value="">Select staff member</option>
              {staff.map((member) => <option key={member.id} value={member.id}>{member.full_name} ({member.role})</option>)}
            </select>
          </div>
          <div className="flex justify-end space-x-3 pt-4">
            <button type="button" onClick={handleCloseModal} className="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">Cancel</button>
            <button type="submit" className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">{editingCustomer ? 'Update' : 'Add'} Customer</button>
          </div>
        </form>
      </Modal>
    </div>
  )
}
