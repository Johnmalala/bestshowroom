import React, { useState, useEffect, useMemo } from 'react'
import { supabase, Car, Broker } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth'
import { formatKES } from '../utils/currency'
import { Plus, Edit, Eye, Upload } from 'lucide-react'
import { Modal } from '../components/ui/Modal'
import { DataTable } from '../components/ui/DataTable'
import { ColumnDef } from '@tanstack/react-table'
import toast from 'react-hot-toast'

export const Cars: React.FC = () => {
  const { isOwner, isManager, profile } = useAuth()
  const [cars, setCars] = useState<Car[]>([])
  const [brokers, setBrokers] = useState<Broker[]>([])
  const [loading, setLoading] = useState(true)
  const [showModal, setShowModal] = useState(false)
  const [editingCar, setEditingCar] = useState<Car | null>(null)

  const [formData, setFormData] = useState({
    car_type: '',
    model_number: '',
    registration_number: '',
    purchase_price: '',
    hire_purchase_deposit: '',
    payment_period_months: '',
    broker_id: '',
    broker_commission_type: 'fixed' as 'fixed' | 'percentage',
    broker_commission_value: '',
    logbook_url: ''
  })

  useEffect(() => {
    fetchCars()
    if (isOwner) {
      fetchBrokers()
    }
  }, [isOwner])

  const fetchCars = async () => {
    try {
      setLoading(true)
      const { data, error } = await supabase
        .from('cars')
        .select(`*, broker:brokers(*)`)
        .order('created_at', { ascending: false })

      if (error) throw error
      setCars(data || [])
    } catch (error) {
      console.error('Error fetching cars:', error)
      toast.error('Failed to fetch cars.')
    } finally {
      setLoading(false)
    }
  }

  const fetchBrokers = async () => {
    try {
      const { data, error } = await supabase
        .from('brokers')
        .select('*')
        .order('name')

      if (error) throw error
      setBrokers(data || [])
    } catch (error) {
      console.error('Error fetching brokers:', error)
      toast.error('Failed to fetch brokers.')
    }
  }

  const handleCloseModal = () => {
    setShowModal(false)
    setEditingCar(null)
    resetForm()
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const toastId = toast.loading(editingCar ? 'Updating car...' : 'Adding car...');
    
    try {
      const carData = {
        car_type: formData.car_type,
        model_number: formData.model_number,
        registration_number: formData.registration_number,
        purchase_price: parseFloat(formData.purchase_price),
        hire_purchase_deposit: formData.hire_purchase_deposit ? parseFloat(formData.hire_purchase_deposit) : null,
        payment_period_months: formData.payment_period_months ? parseInt(formData.payment_period_months) : null,
        broker_id: formData.broker_id || null,
        broker_commission_type: formData.broker_commission_value ? formData.broker_commission_type : null,
        broker_commission_value: formData.broker_commission_value ? parseFloat(formData.broker_commission_value) : null,
        logbook_url: formData.logbook_url || null,
        created_by: profile?.id
      }

      if (editingCar) {
        const { error } = await supabase.from('cars').update(carData).eq('id', editingCar.id)
        if (error) throw error
        toast.success('Car updated successfully!', { id: toastId });
      } else {
        const { error } = await supabase.from('cars').insert([carData])
        if (error) throw error
        toast.success('Car added successfully!', { id: toastId });
      }

      handleCloseModal()
      fetchCars()
    } catch (error: any) {
      toast.error(`Error: ${error.message}`, { id: toastId });
    }
  }

  const resetForm = () => {
    setFormData({
      car_type: '',
      model_number: '',
      registration_number: '',
      purchase_price: '',
      hire_purchase_deposit: '',
      payment_period_months: '',
      broker_id: '',
      broker_commission_type: 'fixed',
      broker_commission_value: '',
      logbook_url: ''
    })
  }

  const handleEdit = (car: Car) => {
    setEditingCar(car)
    setFormData({
      car_type: car.car_type,
      model_number: car.model_number,
      registration_number: car.registration_number,
      purchase_price: car.purchase_price.toString(),
      hire_purchase_deposit: car.hire_purchase_deposit?.toString() || '',
      payment_period_months: car.payment_period_months?.toString() || '',
      broker_id: car.broker_id || '',
      broker_commission_type: car.broker_commission_type || 'fixed',
      broker_commission_value: car.broker_commission_value?.toString() || '',
      logbook_url: car.logbook_url || ''
    })
    setShowModal(true)
  }

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    const toastId = toast.loading('Uploading logbook...');

    try {
      const fileExt = file.name.split('.').pop()
      const fileName = `${Math.random()}.${fileExt}`
      const filePath = `logbooks/${fileName}`

      const { error: uploadError } = await supabase.storage.from('documents').upload(filePath, file)
      if (uploadError) throw uploadError

      const { data } = supabase.storage.from('documents').getPublicUrl(filePath)
      setFormData(prev => ({ ...prev, logbook_url: data.publicUrl }))
      toast.success('Logbook uploaded!', { id: toastId });
    } catch (error: any) {
      toast.error(`Upload failed: ${error.message}`, { id: toastId });
    }
  }

  const columns = useMemo<ColumnDef<Car>[]>(() => [
    {
      accessorKey: 'car_type',
      header: 'Car Details',
      cell: ({ row }) => (
        <div>
          <div className="text-sm font-medium text-gray-900">{row.original.car_type} - {row.original.model_number}</div>
          <div className="text-sm text-gray-500">{row.original.registration_number}</div>
        </div>
      )
    },
    {
      accessorKey: 'purchase_price',
      header: 'Price Info',
      cell: ({ row }) => (
        <div className="text-sm text-gray-900">
          <div>Price: {formatKES(row.original.purchase_price)}</div>
          {row.original.hire_purchase_deposit && <div className="text-gray-500">Deposit: {formatKES(row.original.hire_purchase_deposit)}</div>}
          {row.original.payment_period_months && <div className="text-gray-500">Period: {row.original.payment_period_months} months</div>}
        </div>
      )
    },
    {
      accessorKey: 'broker.name',
      header: 'Broker Commission',
      cell: ({ row }) => (
        isOwner && row.original.broker_commission_value ? (
          <div className="text-sm text-gray-500">
            {row.original.broker?.name && <div>{row.original.broker.name}</div>}
            <div>{row.original.broker_commission_type === 'fixed' ? formatKES(row.original.broker_commission_value) : `${row.original.broker_commission_value}%`}</div>
          </div>
        ) : (<span className="text-sm text-gray-500">No commission</span>)
      )
    },
    {
      accessorKey: 'status',
      header: 'Status',
      cell: ({ row }) => (
        <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${row.original.status === 'available' ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}`}>
          {row.original.status}
        </span>
      )
    },
    {
      id: 'actions',
      header: 'Actions',
      cell: ({ row }) => (
        <div className="flex space-x-2">
          {row.original.logbook_url && <a href={row.original.logbook_url} target="_blank" rel="noopener noreferrer" className="text-blue-600 hover:text-blue-900 p-1"><Eye className="h-4 w-4" /></a>}
          {(isOwner || isManager) && <button onClick={() => handleEdit(row.original)} className="text-indigo-600 hover:text-indigo-900 p-1"><Edit className="h-4 w-4" /></button>}
        </div>
      )
    }
  ], [isOwner, isManager])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="sm:flex sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Cars</h1>
          <p className="mt-1 text-sm text-gray-500">
            Manage your vehicle inventory.
          </p>
        </div>
        {(isOwner || isManager) && (
          <div className="mt-4 sm:mt-0">
            <button
              onClick={() => setShowModal(true)}
              className="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700"
            >
              <Plus className="h-4 w-4 mr-2" />
              Add Car
            </button>
          </div>
        )}
      </div>

      <DataTable columns={columns} data={cars} />

      <Modal isOpen={showModal} onClose={handleCloseModal} title={editingCar ? 'Edit Car' : 'Add New Car'}>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700">Car Type</label>
              <input type="text" required className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.car_type} onChange={(e) => setFormData(prev => ({ ...prev, car_type: e.target.value }))} />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Model Number</label>
              <input type="text" required className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.model_number} onChange={(e) => setFormData(prev => ({ ...prev, model_number: e.target.value }))} />
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700">Registration Number</label>
            <input type="text" required className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.registration_number} onChange={(e) => setFormData(prev => ({ ...prev, registration_number: e.target.value }))} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700">Purchase Price (KES)</label>
              <input type="number" required className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.purchase_price} onChange={(e) => setFormData(prev => ({ ...prev, purchase_price: e.target.value }))} />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700">Hire Purchase Deposit (KES)</label>
              <input type="number" className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.hire_purchase_deposit} onChange={(e) => setFormData(prev => ({ ...prev, hire_purchase_deposit: e.target.value }))} />
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700">Payment Period (months)</label>
            <input type="number" className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.payment_period_months} onChange={(e) => setFormData(prev => ({ ...prev, payment_period_months: e.target.value }))} />
          </div>
          {isOwner && (
            <>
              <div>
                <label className="block text-sm font-medium text-gray-700">Broker</label>
                <select className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.broker_id} onChange={(e) => setFormData(prev => ({ ...prev, broker_id: e.target.value }))}>
                  <option value="">No Broker</option>
                  {brokers.map((broker) => <option key={broker.id} value={broker.id}>{broker.name}</option>)}
                </select>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700">Commission Type</label>
                  <select className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.broker_commission_type} onChange={(e) => setFormData(prev => ({ ...prev, broker_commission_type: e.target.value as 'fixed' | 'percentage' }))}>
                    <option value="fixed">Fixed Amount (KES)</option>
                    <option value="percentage">Percentage (%)</option>
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700">Commission Value</label>
                  <input type="number" step="0.01" className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.broker_commission_value} onChange={(e) => setFormData(prev => ({ ...prev, broker_commission_value: e.target.value }))} />
                </div>
              </div>
            </>
          )}
          <div>
            <label className="block text-sm font-medium text-gray-700">Logbook</label>
            <div className="mt-1 flex items-center space-x-2">
              <input type="file" accept=".jpg,.jpeg,.png,.pdf" onChange={handleFileUpload} className="block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100" />
              <Upload className="h-5 w-5 text-gray-400" />
            </div>
            {formData.logbook_url && <p className="mt-1 text-sm text-green-600">File uploaded successfully</p>}
          </div>
          <div className="flex justify-end space-x-3 pt-4">
            <button type="button" onClick={handleCloseModal} className="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">Cancel</button>
            <button type="submit" className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">{editingCar ? 'Update' : 'Add'} Car</button>
          </div>
        </form>
      </Modal>
    </div>
  )
}
