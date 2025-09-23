/*
# Showroom Management System Database Schema
This migration creates the complete database structure for the Kenyan car dealership showroom management system.

## Query Description:
This operation will create all necessary tables for managing cars, customers, staff, brokers, and payments in the showroom system. This includes user roles, authentication integration, and all business logic tables. No existing data will be affected as this is the initial schema creation.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true

## Structure Details:
- staff_profiles: User profiles linked to auth.users with roles
- brokers: Broker information and commission tracking
- cars: Vehicle inventory with logbook storage
- customers: Customer records and purchase tracking
- payments: Payment history with different payment types
- broker_commissions: Commission tracking per car/broker

## Security Implications:
- RLS Status: Enabled on all tables
- Policy Changes: Yes
- Auth Requirements: All tables require authentication

## Performance Impact:
- Indexes: Added on foreign keys and search columns
- Triggers: Profile creation trigger on auth.users
- Estimated Impact: Minimal for new schema
*/

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create custom types
CREATE TYPE user_role AS ENUM ('owner', 'manager', 'sales');
CREATE TYPE car_status AS ENUM ('available', 'sold');
CREATE TYPE payment_type AS ENUM ('full_purchase', 'hire_purchase_deposit', 'hire_purchase_installment');
CREATE TYPE commission_type AS ENUM ('fixed', 'percentage');

-- Staff profiles table (linked to auth.users)
CREATE TABLE staff_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    phone_number TEXT NOT NULL,
    role user_role NOT NULL DEFAULT 'sales',
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Brokers table
CREATE TABLE brokers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    phone_number TEXT NOT NULL,
    total_commission_due DECIMAL(15,2) DEFAULT 0,
    total_commission_paid DECIMAL(15,2) DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Cars table
CREATE TABLE cars (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    car_type TEXT NOT NULL,
    model_number TEXT NOT NULL,
    registration_number TEXT UNIQUE NOT NULL,
    purchase_price DECIMAL(15,2) NOT NULL,
    hire_purchase_deposit DECIMAL(15,2),
    payment_period_months INTEGER,
    broker_id UUID REFERENCES brokers(id),
    broker_commission_type commission_type,
    broker_commission_value DECIMAL(15,2),
    status car_status DEFAULT 'available',
    logbook_url TEXT,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Customers table
CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name TEXT NOT NULL,
    phone_number TEXT NOT NULL,
    email TEXT,
    car_id UUID REFERENCES cars(id),
    deposit_paid DECIMAL(15,2) DEFAULT 0,
    remaining_balance DECIMAL(15,2) DEFAULT 0,
    hire_purchase_start_date DATE,
    hire_purchase_end_date DATE,
    served_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Payments table
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
    car_id UUID REFERENCES cars(id),
    payment_type payment_type NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    payment_date DATE NOT NULL DEFAULT CURRENT_DATE,
    received_by UUID REFERENCES auth.users(id),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Broker commissions table
CREATE TABLE broker_commissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    broker_id UUID REFERENCES brokers(id) ON DELETE CASCADE,
    car_id UUID REFERENCES cars(id) ON DELETE CASCADE,
    commission_amount DECIMAL(15,2) NOT NULL,
    is_paid BOOLEAN DEFAULT FALSE,
    paid_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_cars_status ON cars(status);
CREATE INDEX idx_cars_registration ON cars(registration_number);
CREATE INDEX idx_customers_phone ON customers(phone_number);
CREATE INDEX idx_payments_customer ON payments(customer_id);
CREATE INDEX idx_payments_date ON payments(payment_date);
CREATE INDEX idx_staff_role ON staff_profiles(role);
CREATE INDEX idx_broker_commissions_broker ON broker_commissions(broker_id);

-- Enable RLS on all tables
ALTER TABLE staff_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE brokers ENABLE ROW LEVEL SECURITY;
ALTER TABLE cars ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE broker_commissions ENABLE ROW LEVEL SECURITY;

-- RLS Policies

-- Staff profiles policies
CREATE POLICY "Staff can view all staff profiles" ON staff_profiles
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Only owners can insert staff profiles" ON staff_profiles
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM staff_profiles 
            WHERE id = auth.uid() AND role = 'owner'
        )
    );

CREATE POLICY "Only owners can update staff profiles" ON staff_profiles
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM staff_profiles 
            WHERE id = auth.uid() AND role = 'owner'
        )
    );

CREATE POLICY "Only owners can delete staff profiles" ON staff_profiles
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM staff_profiles 
            WHERE id = auth.uid() AND role = 'owner'
        )
    );

-- Brokers policies (only owners can access)
CREATE POLICY "Only owners can access brokers" ON brokers
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM staff_profiles 
            WHERE id = auth.uid() AND role = 'owner'
        )
    );

-- Cars policies
CREATE POLICY "All authenticated users can view cars" ON cars
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "Owners and managers can insert cars" ON cars
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM staff_profiles 
            WHERE id = auth.uid() AND role IN ('owner', 'manager')
        )
    );

CREATE POLICY "Owners and managers can update cars" ON cars
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM staff_profiles 
            WHERE id = auth.uid() AND role IN ('owner', 'manager')
        )
    );

CREATE POLICY "Only owners can delete cars" ON cars
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM staff_profiles 
            WHERE id = auth.uid() AND role = 'owner'
        )
    );

-- Customers policies
CREATE POLICY "All authenticated users can view customers" ON customers
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "All authenticated users can insert customers" ON customers
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Owners and managers can update customers" ON customers
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM staff_profiles 
            WHERE id = auth.uid() AND role IN ('owner', 'manager')
        )
    );

CREATE POLICY "Only owners can delete customers" ON customers
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM staff_profiles 
            WHERE id = auth.uid() AND role = 'owner'
        )
    );

-- Payments policies
CREATE POLICY "All authenticated users can view payments" ON payments
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "All authenticated users can insert payments" ON payments
    FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Owners and managers can update payments" ON payments
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM staff_profiles 
            WHERE id = auth.uid() AND role IN ('owner', 'manager')
        )
    );

CREATE POLICY "Only owners can delete payments" ON payments
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM staff_profiles 
            WHERE id = auth.uid() AND role = 'owner'
        )
    );

-- Broker commissions policies (only owners)
CREATE POLICY "Only owners can access broker commissions" ON broker_commissions
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM staff_profiles 
            WHERE id = auth.uid() AND role = 'owner'
        )
    );

-- Functions and triggers

-- Function to automatically create staff profile
CREATE OR REPLACE FUNCTION create_staff_profile()
RETURNS TRIGGER AS $$
BEGIN
    -- Only create profile if user has specific metadata
    IF NEW.raw_user_meta_data ? 'role' THEN
        INSERT INTO staff_profiles (id, full_name, phone_number, role, created_by)
        VALUES (
            NEW.id,
            COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
            COALESCE(NEW.raw_user_meta_data->>'phone_number', ''),
            (NEW.raw_user_meta_data->>'role')::user_role,
            COALESCE((NEW.raw_user_meta_data->>'created_by')::UUID, NEW.id)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for automatic profile creation
CREATE TRIGGER create_staff_profile_trigger
    AFTER INSERT ON auth.users
    FOR EACH ROW
    WHEN (NEW.email_confirmed_at IS NOT NULL)
    EXECUTE FUNCTION create_staff_profile();

-- Function to update timestamps
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add update triggers
CREATE TRIGGER update_staff_profiles_updated_at
    BEFORE UPDATE ON staff_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_brokers_updated_at
    BEFORE UPDATE ON brokers
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_cars_updated_at
    BEFORE UPDATE ON cars
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_customers_updated_at
    BEFORE UPDATE ON customers
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- Function to calculate broker commission
CREATE OR REPLACE FUNCTION calculate_broker_commission(
    car_uuid UUID
) RETURNS DECIMAL AS $$
DECLARE
    car_record RECORD;
    commission_amount DECIMAL(15,2);
BEGIN
    SELECT * INTO car_record FROM cars WHERE id = car_uuid;
    
    IF car_record.broker_commission_type = 'fixed' THEN
        commission_amount := car_record.broker_commission_value;
    ELSIF car_record.broker_commission_type = 'percentage' THEN
        commission_amount := (car_record.purchase_price * car_record.broker_commission_value) / 100;
    ELSE
        commission_amount := 0;
    END IF;
    
    RETURN commission_amount;
END;
$$ LANGUAGE plpgsql;

-- Function to update car status and create commission record
CREATE OR REPLACE FUNCTION handle_car_sale()
RETURNS TRIGGER AS $$
DECLARE
    commission_amount DECIMAL(15,2);
BEGIN
    -- If payment is full purchase, mark car as sold
    IF NEW.payment_type = 'full_purchase' THEN
        UPDATE cars SET status = 'sold' WHERE id = NEW.car_id;
        
        -- Create broker commission record if broker exists
        SELECT calculate_broker_commission(NEW.car_id) INTO commission_amount;
        
        IF commission_amount > 0 THEN
            INSERT INTO broker_commissions (broker_id, car_id, commission_amount)
            SELECT broker_id, NEW.car_id, commission_amount
            FROM cars 
            WHERE id = NEW.car_id AND broker_id IS NOT NULL;
            
            -- Update broker totals
            UPDATE brokers 
            SET total_commission_due = total_commission_due + commission_amount
            WHERE id = (SELECT broker_id FROM cars WHERE id = NEW.car_id);
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for car sale handling
CREATE TRIGGER handle_car_sale_trigger
    AFTER INSERT ON payments
    FOR EACH ROW
    EXECUTE FUNCTION handle_car_sale();
