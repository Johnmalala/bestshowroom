import React, { useState, useEffect } from 'react'
import { supabase, Car } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth'
import { formatKES } from '../utils/currency'
import { Plus, Search, Edit, Eye, Upload } from 'lucide-react'

export const Cars: React.FC = () => {
  const { isOwner, isManager, profile } = useAuth()
  const [cars, setCars] = useState<Car[]>([])
  const [brokers, setBrokers] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [searchTerm, setSearchTerm] = useState('')
  const [showAddModal, setShowAddModal] = useState(false)
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
  }, [])

  const fetchCars = async () => {
    try {
      const { data, error } = await supabase
        .from('cars')
        .select(`
          *,
          broker:brokers(*)
        `)
        .order('created_at', { ascending: false })

      if (error) throw error
      setCars(data || [])
    } catch (error) {
      console.error('Error fetching cars:', error)
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
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
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
        const { error } = await supabase
          .from('cars')
          .update(carData)
          .eq('id', editingCar.id)

        if (error) throw error
      } else {
        const { error } = await supabase
          .from('cars')
          .insert([carData])

        if (error) throw error
      }

      setShowAddModal(false)
      setEditingCar(null)
      resetForm()
      fetchCars()
    } catch (error: any) {
      alert('Error saving car: ' + error.message)
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
    setShowAddModal(true)
  }

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    try {
      const fileExt = file.name.split('.').pop()
      const fileName = `${Math.random()}.${fileExt}`
      const filePath = `logbooks/${fileName}`

      const { error: uploadError } = await supabase.storage
        .from('documents')
        .upload(filePath, file)

      if (uploadError) throw uploadError

      const { data } = supabase.storage
        .from('documents')
        .getPublicUrl(filePath)

      setFormData(prev => ({ ...prev, logbook_url: data.publicUrl }))
    } catch (error: any) {
      alert('Error uploading file: ' + error.message)
    }
  }

  const filteredCars = cars.filter(car =>
    car.car_type.toLowerCase().includes(searchTerm.toLowerCase()) ||
    car.model_number.toLowerCase().includes(searchTerm.toLowerCase()) ||
    car.registration_number.toLowerCase().includes(searchTerm.toLowerCase())
  )

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
            Manage your vehicle inventory
          </p>
        </div>
        {(isOwner || isManager) && (
          <div className="mt-4 sm:mt-0">
            <button
              onClick={() => setShowAddModal(true)}
              className="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700"
            >
              <Plus className="h-4 w-4 mr-2" />
              Add Car
            </button>
          </div>
        )}
      </div>

      {/* Search */}
      <div className="max-w-md">
        <div className="relative">
          <Search className="h-5 w-5 absolute left-3 top-3 text-gray-400" />
          <input
            type="text"
            placeholder="Search cars..."
            className="pl-10 pr-4 py-2 w-full border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>
      </div>

      {/* Cars Table */}
      <div className="bg-white shadow overflow-hidden sm:rounded-md">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Car Details
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Price Info
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Broker Commission
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {filteredCars.map((car) => (
                <tr key={car.id}>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div>
                      <div className="text-sm font-medium text-gray-900">
                        {car.car_type} - {car.model_number}
                      </div>
                      <div className="text-sm text-gray-500">
                        {car.registration_number}
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm text-gray-900">
                      <div>Price: {formatKES(car.purchase_price)}</div>
                      {car.hire_purchase_deposit && (
                        <div className="text-gray-500">
                          Deposit: {formatKES(car.hire_purchase_deposit)}
                        </div>
                      )}
                      {car.payment_period_months && (
                        <div className="text-gray-500">
                          Period: {car.payment_period_months} months
                        </div>
                      )}
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {isOwner && car.broker_commission_value ? (
                      <div>
                        {car.broker?.name && <div>{car.broker.name}</div>}
                        <div>
                          {car.broker_commission_type === 'fixed' 
                            ? formatKES(car.broker_commission_value)
                            : `${car.broker_commission_value}%`}
                        </div>
                      </div>
                    ) : (
                      'No commission'
                    )}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                      car.status === 'available' 
                        ? 'bg-green-100 text-green-800'
                        : 'bg-red-100 text-red-800'
                    }`}>
                      {car.status}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                    <div className="flex space-x-2">
                      {car.logbook_url && (
                        <a
                          href={car.logbook_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-blue-600 hover:text-blue-900"
                        >
                          <Eye className="h-4 w-4" />
                        </a>
                      )}
                      {(isOwner || isManager) && (
                        <button
                          onClick={() => handleEdit(car)}
                          className="text-indigo-600 hover:text-indigo-900"
                        >
                          <Edit className="h-4 w-4" />
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Add/Edit Modal */}
      {showAddModal && (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50">
          <div className="relative top-20 mx-auto p-5 border w-11/12 max-w-lg shadow-lg rounded-md bg-white">
            <h3 className="text-lg font-bold text-gray-900 mb-4">
              {editingCar ? 'Edit Car' : 'Add New Car'}
            </h3>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700">Car Type</label>
                  <input
                    type="text"
                    required
                    className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                    value={formData.car_type}
                    onChange={(e) => setFormData(prev => ({ ...prev, car_type: e.target.value }))}
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700">Model Number</label>
                  <input
                    type="text"
                    required
                    className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                    value={formData.model_number}
                    onChange={(e) => setFormData(prev => ({ ...prev, model_number: e.target.value }))}
                  />
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Registration Number</label>
                <input
                  type="text"
                  required
                  className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                  value={formData.registration_number}
                  onChange={(e) => setFormData(prev => ({ ...prev, registration_number: e.target.value }))}
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700">Purchase Price (KES)</label>
                  <input
                    type="number"
                    required
                    className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                    value={formData.purchase_price}
                    onChange={(e) => setFormData(prev => ({ ...prev, purchase_price: e.target.value }))}
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700">Hire Purchase Deposit (KES)</label>
                  <input
                    type="number"
                    className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                    value={formData.hire_purchase_deposit}
                    onChange={(e) => setFormData(prev => ({ ...prev, hire_purchase_deposit: e.target.value }))}
                  />
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Payment Period (months)</label>
                <input
                  type="number"
                  className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                  value={formData.payment_period_months}
                  onChange={(e) => setFormData(prev => ({ ...prev, payment_period_months: e.target.value }))}
                />
              </div>

              {isOwner && (
                <>
                  <div>
                    <label className="block text-sm font-medium text-gray-700">Broker</label>
                    <select
                      className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                      value={formData.broker_id}
                      onChange={(e) => setFormData(prev => ({ ...prev, broker_id: e.target.value }))}
                    >
                      <option value="">No Broker</option>
                      {brokers.map((broker) => (
                        <option key={broker.id} value={broker.id}>
                          {broker.name}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <label className="block text-sm font-medium text-gray-700">Commission Type</label>
                      <select
                        className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                        value={formData.broker_commission_type}
                        onChange={(e) => setFormData(prev => ({ ...prev, broker_commission_type: e.target.value as 'fixed' | 'percentage' }))}
                      >
                        <option value="fixed">Fixed Amount (KES)</option>
                        <option value="percentage">Percentage (%)</option>
                      </select>
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-gray-700">Commission Value</label>
                      <input
                        type="number"
                        step="0.01"
                        className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                        value={formData.broker_commission_value}
                        onChange={(e) => setFormData(prev => ({ ...prev, broker_commission_value: e.target.value }))}
                      />
                    </div>
                  </div>
                </>
              )}

              <div>
                <label className="block text-sm font-medium text-gray-700">Logbook</label>
                <div className="mt-1 flex items-center space-x-2">
                  <input
                    type="file"
                    accept=".jpg,.jpeg,.png,.pdf"
                    onChange={handleFileUpload}
                    className="block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100"
                  />
                  <Upload className="h-5 w-5 text-gray-400" />
                </div>
                {formData.logbook_url && (
                  <p className="mt-1 text-sm text-green-600">File uploaded successfully</p>
                )}
              </div>

              <div className="flex justify-end space-x-3 pt-4">
                <button
                  type="button"
                  onClick={() => {
                    setShowAddModal(false)
                    setEditingCar(null)
                    resetForm()
                  }}
                  className="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700"
                >
                  {editingCar ? 'Update' : 'Add'} Car
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  )
}
