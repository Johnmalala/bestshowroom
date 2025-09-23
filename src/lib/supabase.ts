import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const supabase = createClient(supabaseUrl, supabaseAnonKey)

// Types
export type UserRole = 'owner' | 'manager' | 'sales'
export type CarStatus = 'available' | 'sold'
export type PaymentType = 'full_purchase' | 'hire_purchase_deposit' | 'hire_purchase_installment'
export type CommissionType = 'fixed' | 'percentage'

export interface StaffProfile {
  id: string
  full_name: string
  phone_number: string
  role: UserRole
  created_by?: string
  created_at: string
  updated_at: string
}

export interface Broker {
  id: string
  name: string
  phone_number: string
  total_commission_due: number
  total_commission_paid: number
  created_at: string
  updated_at: string
}

export interface Car {
  id: string
  car_type: string
  model_number: string
  registration_number: string
  purchase_price: number
  hire_purchase_deposit?: number
  payment_period_months?: number
  broker_id?: string
  broker_commission_type?: CommissionType
  broker_commission_value?: number
  status: CarStatus
  logbook_url?: string
  created_by?: string
  created_at: string
  updated_at: string
  broker?: Broker
}

export interface Customer {
  id: string
  full_name: string
  phone_number: string
  email?: string
  car_id?: string
  deposit_paid: number
  remaining_balance: number
  hire_purchase_start_date?: string
  hire_purchase_end_date?: string
  served_by?: string
  created_at: string
  updated_at: string
  car?: Car
  staff?: StaffProfile
}

export interface Payment {
  id: string
  customer_id: string
  car_id?: string
  payment_type: PaymentType
  amount: number
  payment_date: string
  received_by?: string
  notes?: string
  created_at: string
  customer?: Customer
  car?: Car
  staff?: StaffProfile
}

export interface BrokerCommission {
  id: string
  broker_id: string
  car_id: string
  commission_amount: number
  is_paid: boolean
  paid_date?: string
  created_at: string
  broker?: Broker
  car?: Car
}
