import React, { useState, useEffect, useMemo } from 'react'
import { supabase, Broker, BrokerCommission } from '../lib/supabase'
import { formatKES } from '../utils/currency'
import { Plus, Edit, UserCheck, DollarSign } from 'lucide-react'
import { Modal } from '../components/ui/Modal'
import { DataTable } from '../components/ui/DataTable'
import { ColumnDef } from '@tanstack/react-table'
import { format } from 'date-fns'
import toast from 'react-hot-toast'

export const Brokers: React.FC = () => {
  const [brokers, setBrokers] = useState<Broker[]>([])
  const [commissions, setCommissions] = useState<BrokerCommission[]>([])
  const [loading, setLoading] = useState(true)
  const [showModal, setShowModal] = useState(false)
  const [editingBroker, setEditingBroker] = useState<Broker | null>(null)
  
  const [formData, setFormData] = useState({ name: '', phone_number: '' })

  useEffect(() => {
    fetchBrokers()
    fetchCommissions()
  }, [])

  const fetchBrokers = async () => {
    try {
      setLoading(true)
      const { data, error } = await supabase.from('brokers').select('*').order('name')
      if (error) throw error
      setBrokers(data || [])
    } catch (error) {
      console.error('Error fetching brokers:', error)
      toast.error('Failed to fetch brokers.')
    } finally {
      setLoading(false)
    }
  }

  const fetchCommissions = async () => {
    try {
      const { data, error } = await supabase.from('broker_commissions').select(`*, broker:brokers(*), car:cars(*)`).order('created_at', { ascending: false })
      if (error) throw error
      setCommissions(data || [])
    } catch (error) {
      console.error('Error fetching commissions:', error)
      toast.error('Failed to fetch commissions.')
    }
  }

  const handleCloseModal = () => {
    setShowModal(false)
    setEditingBroker(null)
    resetForm()
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const toastId = toast.loading(editingBroker ? 'Updating broker...' : 'Adding broker...');
    
    try {
      const brokerData = { name: formData.name, phone_number: formData.phone_number }

      if (editingBroker) {
        const { error } = await supabase.from('brokers').update(brokerData).eq('id', editingBroker.id)
        if (error) throw error
        toast.success('Broker updated successfully!', { id: toastId });
      } else {
        const { error } = await supabase.from('brokers').insert([brokerData])
        if (error) throw error
        toast.success('Broker added successfully!', { id: toastId });
      }

      handleCloseModal()
      fetchBrokers()
    } catch (error: any) {
      toast.error(`Error: ${error.message}`, { id: toastId });
    }
  }

  const resetForm = () => setFormData({ name: '', phone_number: '' })

  const handleEdit = (broker: Broker) => {
    setEditingBroker(broker)
    setFormData({ name: broker.name, phone_number: broker.phone_number })
    setShowModal(true)
  }

  const markCommissionPaid = async (commissionId: string, brokerId: string, amount: number) => {
    if (!window.confirm(`Mark this commission of ${formatKES(amount)} as paid?`)) return
    
    const toastId = toast.loading('Processing payment...');

    try {
      const { error: commissionError } = await supabase.from('broker_commissions').update({ is_paid: true, paid_date: new Date().toISOString() }).eq('id', commissionId)
      if (commissionError) throw commissionError

      const { error: brokerError } = await supabase.rpc('update_broker_totals', {
        p_broker_id: brokerId,
        p_amount: amount,
      })
      if (brokerError) throw brokerError
      
      toast.success('Commission marked as paid!', { id: toastId });
      fetchBrokers()
      fetchCommissions()
    } catch (error: any) {
      toast.error(`Error: ${error.message}`, { id: toastId });
    }
  }

  const brokerColumns = useMemo<ColumnDef<Broker>[]>(() => [
    {
      accessorKey: 'name',
      header: 'Broker',
      cell: ({ row }) => (
        <div className="flex items-center">
          <div className="h-10 w-10 rounded-full bg-gray-100 flex items-center justify-center"><UserCheck className="h-6 w-6 text-gray-400" /></div>
          <div className="ml-4">
            <div className="text-sm font-medium text-gray-900">{row.original.name}</div>
            <div className="text-sm text-gray-500">{row.original.phone_number}</div>
          </div>
        </div>
      )
    },
    {
      accessorKey: 'total_commission_due',
      header: 'Commission Due',
      cell: ({ row }) => <div className="text-sm font-medium text-red-600">{formatKES(row.original.total_commission_due)}</div>
    },
    {
      accessorKey: 'total_commission_paid',
      header: 'Commission Paid',
      cell: ({ row }) => <div className="text-sm font-medium text-green-600">{formatKES(row.original.total_commission_paid)}</div>
    },
    {
      id: 'actions',
      header: 'Actions',
      cell: ({ row }) => <button onClick={() => handleEdit(row.original)} className="text-indigo-600 hover:text-indigo-900 p-1"><Edit className="h-4 w-4" /></button>
    }
  ], [])

  const commissionColumns = useMemo<ColumnDef<BrokerCommission>[]>(() => [
    {
      accessorKey: 'broker.name',
      header: 'Broker',
      cell: ({ row }) => <div className="text-sm font-medium text-gray-900">{row.original.broker?.name}</div>
    },
    {
      accessorKey: 'car.car_type',
      header: 'Car',
      cell: ({ row }) => row.original.car ? (
        <div className="text-sm">
          <div className="text-gray-900">{row.original.car.car_type}</div>
          <div className="text-gray-500">{row.original.car.registration_number}</div>
        </div>
      ) : null
    },
    {
      accessorKey: 'commission_amount',
      header: 'Amount',
      cell: ({ row }) => <div className="text-sm font-medium text-gray-900">{formatKES(row.original.commission_amount)}</div>
    },
    {
      accessorKey: 'is_paid',
      header: 'Status',
      cell: ({ row }) => (
        <div>
          <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${row.original.is_paid ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}`}>
            {row.original.is_paid ? 'Paid' : 'Pending'}
          </span>
          {row.original.paid_date && <div className="text-xs text-gray-500 mt-1">{format(new Date(row.original.paid_date), 'PP')}</div>}
        </div>
      )
    },
    {
      id: 'actions',
      header: 'Actions',
      cell: ({ row }) => !row.original.is_paid ? (
        <button onClick={() => markCommissionPaid(row.original.id, row.original.broker_id, row.original.commission_amount)} className="text-green-600 hover:text-green-900 p-1 flex items-center gap-1 text-sm">
          <DollarSign className="h-4 w-4" /> Mark Paid
        </button>
      ) : null
    }
  ], [])

  if (loading) {
    return <div className="flex items-center justify-center h-64"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div></div>
  }

  return (
    <div className="space-y-8">
      <div className="sm:flex sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Brokers</h1>
          <p className="mt-1 text-sm text-gray-500">Manage broker information and commissions</p>
        </div>
        <div className="mt-4 sm:mt-0">
          <button onClick={() => setShowModal(true)} className="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
            <Plus className="h-4 w-4 mr-2" /> Add Broker
          </button>
        </div>
      </div>

      <div>
        <h3 className="text-xl font-semibold text-gray-900 mb-4">Broker Overview</h3>
        <DataTable columns={brokerColumns} data={brokers} />
      </div>

      <div>
        <h3 className="text-xl font-semibold text-gray-900 mb-4">Commission Details</h3>
        <DataTable columns={commissionColumns} data={commissions} />
      </div>

      <Modal isOpen={showModal} onClose={handleCloseModal} title={editingBroker ? 'Edit Broker' : 'Add New Broker'}>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700">Name</label>
            <input type="text" required className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.name} onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))} />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700">Phone Number</label>
            <input type="tel" required className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.phone_number} onChange={(e) => setFormData(prev => ({ ...prev, phone_number: e.target.value }))} />
          </div>
          <div className="flex justify-end space-x-3 pt-4">
            <button type="button" onClick={handleCloseModal} className="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">Cancel</button>
            <button type="submit" className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">{editingBroker ? 'Update' : 'Add'} Broker</button>
          </div>
        </form>
      </Modal>
    </div>
  )
}
