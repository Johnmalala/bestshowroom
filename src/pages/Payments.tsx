import React, { useState, useEffect } from 'react'
import { supabase, Payment, Customer, Car, PaymentType } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth'
import { formatKES } from '../utils/currency'
import { Plus, Search, CreditCard, AlertTriangle } from 'lucide-react'

export const Payments: React.FC = () => {
  const { profile } = useAuth()
  const [payments, setPayments] = useState<Payment[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [cars, setCars] = useState<Car[]>([])
  const [loading, setLoading] = useState(true)
  const [searchTerm, setSearchTerm] = useState('')
  const [showAddModal, setShowAddModal] = useState(false)

  const [formData, setFormData] = useState({
    customer_id: '',
    car_id: '',
    payment_type: 'hire_purchase_installment' as PaymentType,
    amount: '',
    payment_date: new Date().toISOString().split('T')[0],
    notes: '',
    received_by: profile?.id || ''
  })

  const [selectedCustomer, setSelectedCustomer] = useState<Customer | null>(null)

  useEffect(() => {
    fetchPayments()
    fetchCustomers()
    fetchCars()
  }, [])

  const fetchPayments = async () => {
    try {
      const { data, error } = await supabase
        .from('payments')
        .select(`
          *,
          customer:customers(*),
          car:cars(*),
          staff:staff_profiles(*)
        `)
        .order('created_at', { ascending: false })

      if (error) throw error
      setPayments(data || [])
    } catch (error) {
      console.error('Error fetching payments:', error)
    } finally {
      setLoading(false)
    }
  }

  const fetchCustomers = async () => {
    try {
      const { data, error } = await supabase
        .from('customers')
        .select(`
          *,
          car:cars(*)
        `)
        .order('full_name')

      if (error) throw error
      setCustomers(data || [])
    } catch (error) {
      console.error('Error fetching customers:', error)
    }
  }

  const fetchCars = async () => {
    try {
      const { data, error } = await supabase
        .from('cars')
        .select('*')
        .eq('status', 'available')
        .order('car_type')

      if (error) throw error
      setCars(data || [])
    } catch (error) {
      console.error('Error fetching cars:', error)
    }
  }

  const handleCustomerChange = (customerId: string) => {
    const customer = customers.find(c => c.id === customerId)
    setSelectedCustomer(customer || null)
    setFormData(prev => ({
      ...prev,
      customer_id: customerId,
      car_id: customer?.car_id || ''
    }))
  }

  const validatePayment = (amount: number): string | null => {
    if (!selectedCustomer) return 'Please select a customer'
    
    if (formData.payment_type === 'full_purchase') {
      const car = cars.find(c => c.id === formData.car_id)
      if (!car) return 'Please select a car'
      
      if (amount !== car.purchase_price) {
        return `Full purchase payment must be exactly ${formatKES(car.purchase_price)}`
      }
    } else if (formData.payment_type === 'hire_purchase_installment') {
      if (amount > selectedCustomer.remaining_balance) {
        return `Payment cannot exceed remaining balance of ${formatKES(selectedCustomer.remaining_balance)}`
      }
    }
    
    return null
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    const amount = parseFloat(formData.amount)
    const validationError = validatePayment(amount)
    
    if (validationError) {
      alert(validationError)
      return
    }

    try {
      const paymentData = {
        customer_id: formData.customer_id,
        car_id: formData.car_id || null,
        payment_type: formData.payment_type,
        amount: amount,
        payment_date: formData.payment_date,
        received_by: formData.received_by || profile?.id,
        notes: formData.notes || null
      }

      const { error } = await supabase
        .from('payments')
        .insert([paymentData])

      if (error) throw error

      // Update customer balance if installment payment
      if (formData.payment_type === 'hire_purchase_installment' && selectedCustomer) {
        const newBalance = selectedCustomer.remaining_balance - amount
        const newDepositPaid = selectedCustomer.deposit_paid + amount

        await supabase
          .from('customers')
          .update({
            remaining_balance: newBalance,
            deposit_paid: newDepositPaid
          })
          .eq('id', selectedCustomer.id)
      }

      setShowAddModal(false)
      resetForm()
      fetchPayments()
      fetchCustomers()
    } catch (error: any) {
      alert('Error saving payment: ' + error.message)
    }
  }

  const resetForm = () => {
    setFormData({
      customer_id: '',
      car_id: '',
      payment_type: 'hire_purchase_installment',
      amount: '',
      payment_date: new Date().toISOString().split('T')[0],
      notes: '',
      received_by: profile?.id || ''
    })
    setSelectedCustomer(null)
  }

  const filteredPayments = payments.filter(payment =>
    payment.customer?.full_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    payment.car?.registration_number.toLowerCase().includes(searchTerm.toLowerCase()) ||
    payment.payment_type.includes(searchTerm.toLowerCase())
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
          <h1 className="text-2xl font-bold text-gray-900">Payments</h1>
          <p className="mt-1 text-sm text-gray-500">
            Record and track customer payments
          </p>
        </div>
        <div className="mt-4 sm:mt-0">
          <button
            onClick={() => setShowAddModal(true)}
            className="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700"
          >
            <Plus className="h-4 w-4 mr-2" />
            Record Payment
          </button>
        </div>
      </div>

      {/* Search */}
      <div className="max-w-md">
        <div className="relative">
          <Search className="h-5 w-5 absolute left-3 top-3 text-gray-400" />
          <input
            type="text"
            placeholder="Search payments..."
            className="pl-10 pr-4 py-2 w-full border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>
      </div>

      {/* Payments Table */}
      <div className="bg-white shadow overflow-hidden sm:rounded-md">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Customer
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Car
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Payment Type
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Amount
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Date
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Received By
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {filteredPayments.map((payment) => (
                <tr key={payment.id}>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="flex items-center">
                      <div className="h-10 w-10 rounded-full bg-gray-100 flex items-center justify-center">
                        <CreditCard className="h-6 w-6 text-gray-400" />
                      </div>
                      <div className="ml-4">
                        <div className="text-sm font-medium text-gray-900">
                          {payment.customer?.full_name}
                        </div>
                        <div className="text-sm text-gray-500">
                          {payment.customer?.phone_number}
                        </div>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    {payment.car ? (
                      <div className="text-sm text-gray-900">
                        <div>{payment.car.car_type} - {payment.car.model_number}</div>
                        <div className="text-gray-500">{payment.car.registration_number}</div>
                      </div>
                    ) : (
                      <span className="text-gray-500">No car specified</span>
                    )}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                      payment.payment_type === 'full_purchase' 
                        ? 'bg-green-100 text-green-800'
                        : payment.payment_type === 'hire_purchase_deposit'
                        ? 'bg-blue-100 text-blue-800'
                        : 'bg-yellow-100 text-yellow-800'
                    }`}>
                      {payment.payment_type.replace(/_/g, ' ')}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    {formatKES(payment.amount)}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {new Date(payment.payment_date).toLocaleDateString()}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {payment.staff?.full_name || 'Not specified'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Add Payment Modal */}
      {showAddModal && (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50">
          <div className="relative top-10 mx-auto p-5 border w-11/12 max-w-lg shadow-lg rounded-md bg-white">
            <h3 className="text-lg font-bold text-gray-900 mb-4">
              Record New Payment
            </h3>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700">Customer</label>
                <select
                  required
                  className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                  value={formData.customer_id}
                  onChange={(e) => handleCustomerChange(e.target.value)}
                >
                  <option value="">Select a customer</option>
                  {customers.map((customer) => (
                    <option key={customer.id} value={customer.id}>
                      {customer.full_name} - {customer.phone_number}
                    </option>
                  ))}
                </select>
              </div>

              {selectedCustomer && (
                <div className="bg-blue-50 p-3 rounded-md">
                  <div className="text-sm">
                    <div><strong>Current Balance:</strong> {formatKES(selectedCustomer.remaining_balance)}</div>
                    <div><strong>Amount Paid:</strong> {formatKES(selectedCustomer.deposit_paid)}</div>
                    {selectedCustomer.car && (
                      <div><strong>Car:</strong> {selectedCustomer.car.car_type} - {selectedCustomer.car.model_number}</div>
                    )}
                  </div>
                </div>
              )}

              <div>
                <label className="block text-sm font-medium text-gray-700">Payment Type</label>
                <select
                  required
                  className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                  value={formData.payment_type}
                  onChange={(e) => setFormData(prev => ({ ...prev, payment_type: e.target.value as PaymentType }))}
                >
                  <option value="hire_purchase_installment">Hire Purchase Installment</option>
                  <option value="hire_purchase_deposit">Hire Purchase Deposit</option>
                  <option value="full_purchase">Full Purchase Payment</option>
                </select>
              </div>

              {formData.payment_type === 'full_purchase' && (
                <div>
                  <label className="block text-sm font-medium text-gray-700">Car</label>
                  <select
                    required
                    className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                    value={formData.car_id}
                    onChange={(e) => setFormData(prev => ({ ...prev, car_id: e.target.value }))}
                  >
                    <option value="">Select a car</option>
                    {cars.map((car) => (
                      <option key={car.id} value={car.id}>
                        {car.car_type} - {car.model_number} ({formatKES(car.purchase_price)})
                      </option>
                    ))}
                  </select>
                </div>
              )}

              <div>
                <label className="block text-sm font-medium text-gray-700">Amount (KES)</label>
                <input
                  type="number"
                  step="0.01"
                  required
                  className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                  value={formData.amount}
                  onChange={(e) => setFormData(prev => ({ ...prev, amount: e.target.value }))}
                />
                {selectedCustomer && formData.amount && parseFloat(formData.amount) > selectedCustomer.remaining_balance && formData.payment_type === 'hire_purchase_installment' && (
                  <div className="mt-1 flex items-center text-red-600 text-sm">
                    <AlertTriangle className="h-4 w-4 mr-1" />
                    Amount exceeds remaining balance
                  </div>
                )}
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Payment Date</label>
                <input
                  type="date"
                  required
                  className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                  value={formData.payment_date}
                  onChange={(e) => setFormData(prev => ({ ...prev, payment_date: e.target.value }))}
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700">Notes (Optional)</label>
                <textarea
                  rows={3}
                  className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                  value={formData.notes}
                  onChange={(e) => setFormData(prev => ({ ...prev, notes: e.target.value }))}
                />
              </div>

              <div className="flex justify-end space-x-3 pt-4">
                <button
                  type="button"
                  onClick={() => {
                    setShowAddModal(false)
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
                  Record Payment
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  )
}
