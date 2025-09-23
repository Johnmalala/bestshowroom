import React, { useState, useEffect } from 'react'
import { supabase, Broker, BrokerCommission } from '../lib/supabase'
import { formatKES } from '../utils/currency'
import { Plus, Search, Edit, UserCheck, DollarSign } from 'lucide-react'

export const Brokers: React.FC = () => {
  const [brokers, setBrokers] = useState<Broker[]>([])
  const [commissions, setCommissions] = useState<BrokerCommission[]>([])
  const [loading, setLoading] = useState(true)
  const [searchTerm, setSearchTerm] = useState('')
  const [showAddModal, setShowAddModal] = useState(false)
  const [editingBroker, setEditingBroker] = useState<Broker | null>(null)
  const [selectedBroker, setSelectedBroker] = useState<string>('')

  const [formData, setFormData] = useState({
    name: '',
    phone_number: ''
  })

  useEffect(() => {
    fetchBrokers()
    fetchCommissions()
  }, [])

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
    } finally {
      setLoading(false)
    }
  }

  const fetchCommissions = async () => {
    try {
      const { data, error } = await supabase
        .from('broker_commissions')
        .select(`
          *,
          broker:brokers(*),
          car:cars(*)
        `)
        .order('created_at', { ascending: false })

      if (error) throw error
      setCommissions(data || [])
    } catch (error) {
      console.error('Error fetching commissions:', error)
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    try {
      const brokerData = {
        name: formData.name,
        phone_number: formData.phone_number
      }

      if (editingBroker) {
        const { error } = await supabase
          .from('brokers')
          .update(brokerData)
          .eq('id', editingBroker.id)

        if (error) throw error
      } else {
        const { error } = await supabase
          .from('brokers')
          .insert([brokerData])

        if (error) throw error
      }

      setShowAddModal(false)
      setEditingBroker(null)
      resetForm()
      fetchBrokers()
    } catch (error: any) {
      alert('Error saving broker: ' + error.message)
    }
  }

  const resetForm = () => {
    setFormData({
      name: '',
      phone_number: ''
    })
  }

  const handleEdit = (broker: Broker) => {
    setEditingBroker(broker)
    setFormData({
      name: broker.name,
      phone_number: broker.phone_number
    })
    setShowAddModal(true)
  }

  const markCommissionPaid = async (commissionId: string, brokerId: string, amount: number) => {
    try {
      // Update commission as paid
      const { error: commissionError } = await supabase
        .from('broker_commissions')
        .update({
          is_paid: true,
          paid_date: new Date().toISOString().split('T')[0]
        })
        .eq('id', commissionId)

      if (commissionError) throw commissionError

      // Update broker totals
      const { error: brokerError } = await supabase
        .from('brokers')
        .update({
          total_commission_paid: brokers.find(b => b.id === brokerId)?.total_commission_paid + amount,
          total_commission_due: brokers.find(b => b.id === brokerId)?.total_commission_due - amount
        })
        .eq('id', brokerId)

      if (brokerError) throw brokerError

      fetchBrokers()
      fetchCommissions()
    } catch (error: any) {
      alert('Error updating commission: ' + error.message)
    }
  }

  const filteredBrokers = brokers.filter(broker =>
    broker.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    broker.phone_number.includes(searchTerm)
  )

  const filteredCommissions = selectedBroker 
    ? commissions.filter(commission => commission.broker_id === selectedBroker)
    : commissions

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
          <h1 className="text-2xl font-bold text-gray-900">Brokers</h1>
          <p className="mt-1 text-sm text-gray-500">
            Manage broker information and commissions
          </p>
        </div>
        <div className="mt-4 sm:mt-0">
          <button
            onClick={() => setShowAddModal(true)}
            className="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700"
          >
            <Plus className="h-4 w-4 mr-2" />
            Add Broker
          </button>
        </div>
      </div>

      {/* Search */}
      <div className="max-w-md">
        <div className="relative">
          <Search className="h-5 w-5 absolute left-3 top-3 text-gray-400" />
          <input
            type="text"
            placeholder="Search brokers..."
            className="pl-10 pr-4 py-2 w-full border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>
      </div>

      {/* Brokers Table */}
      <div className="bg-white shadow overflow-hidden sm:rounded-md">
        <div className="px-4 py-5 sm:p-6">
          <h3 className="text-lg leading-6 font-medium text-gray-900 mb-4">
            Brokers
          </h3>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Broker
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Contact
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Commission Due
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Commission Paid
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {filteredBrokers.map((broker) => (
                  <tr key={broker.id}>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center">
                        <div className="h-10 w-10 rounded-full bg-gray-100 flex items-center justify-center">
                          <UserCheck className="h-6 w-6 text-gray-400" />
                        </div>
                        <div className="ml-4">
                          <div className="text-sm font-medium text-gray-900">
                            {broker.name}
                          </div>
                        </div>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      {broker.phone_number}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-red-600">
                      {formatKES(broker.total_commission_due)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-green-600">
                      {formatKES(broker.total_commission_paid)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                      <button
                        onClick={() => handleEdit(broker)}
                        className="text-indigo-600 hover:text-indigo-900 mr-3"
                      >
                        <Edit className="h-4 w-4" />
                      </button>
                      <button
                        onClick={() => setSelectedBroker(broker.id)}
                        className="text-blue-600 hover:text-blue-900"
                      >
                        <DollarSign className="h-4 w-4" />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {/* Commissions Section */}
      <div className="bg-white shadow overflow-hidden sm:rounded-md">
        <div className="px-4 py-5 sm:p-6">
          <div className="flex justify-between items-center mb-4">
            <h3 className="text-lg leading-6 font-medium text-gray-900">
              Broker Commissions
            </h3>
            <select
              className="border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
              value={selectedBroker}
              onChange={(e) => setSelectedBroker(e.target.value)}
            >
              <option value="">All Brokers</option>
              {brokers.map((broker) => (
                <option key={broker.id} value={broker.id}>
                  {broker.name}
                </option>
              ))}
            </select>
          </div>
          
          {filteredCommissions.length === 0 ? (
            <p className="text-gray-500">No commissions found</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-gray-200">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Broker
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Car
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Commission
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
                  {filteredCommissions.map((commission) => (
                    <tr key={commission.id}>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                        {commission.broker?.name}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        {commission.car && (
                          <div className="text-sm text-gray-900">
                            <div>{commission.car.car_type} - {commission.car.model_number}</div>
                            <div className="text-gray-500">{commission.car.registration_number}</div>
                          </div>
                        )}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                        {formatKES(commission.commission_amount)}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                          commission.is_paid 
                            ? 'bg-green-100 text-green-800'
                            : 'bg-red-100 text-red-800'
                        }`}>
                          {commission.is_paid ? 'Paid' : 'Pending'}
                        </span>
                        {commission.paid_date && (
                          <div className="text-xs text-gray-500 mt-1">
                            Paid: {new Date(commission.paid_date).toLocaleDateString()}
                          </div>
                        )}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                        {!commission.is_paid && (
                          <button
                            onClick={() => markCommissionPaid(commission.id, commission.broker_id, commission.commission_amount)}
                            className="text-green-600 hover:text-green-900"
                          >
                            Mark Paid
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {/* Add/Edit Modal */}
      {showAddModal && (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50">
          <div className="relative top-20 mx-auto p-5 border w-11/12 max-w-lg shadow-lg rounded-md bg-white">
            <h3 className="text-lg font-bold text-gray-900 mb-4">
              {editingBroker ? 'Edit Broker' : 'Add New Broker'}
            </h3>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700">Name</label>
                <input
                  type="text"
                  required
                  className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                  value={formData.name}
                  onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Phone Number</label>
                <input
                  type="tel"
                  required
                  className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                  value={formData.phone_number}
                  onChange={(e) => setFormData(prev => ({ ...prev, phone_number: e.target.value }))}
                />
              </div>

              <div className="flex justify-end space-x-3 pt-4">
                <button
                  type="button"
                  onClick={() => {
                    setShowAddModal(false)
                    setEditingBroker(null)
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
                  {editingBroker ? 'Update' : 'Add'} Broker
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  )
}
