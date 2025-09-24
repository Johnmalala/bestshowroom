import React, { useState, useEffect, useMemo } from 'react'
import { supabase, StaffProfile, UserRole } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth'
import { Plus, Edit, User, Trash2 } from 'lucide-react'
import { Modal } from '../components/ui/Modal'
import { DataTable } from '../components/ui/DataTable'
import { ColumnDef } from '@tanstack/react-table'
import { format } from 'date-fns'
import toast from 'react-hot-toast'

export const Staff: React.FC = () => {
  const { signUp, profile } = useAuth()
  const [staff, setStaff] = useState<StaffProfile[]>([])
  const [loading, setLoading] = useState(true)
  const [showModal, setShowModal] = useState(false)
  const [editingStaff, setEditingStaff] = useState<StaffProfile | null>(null)

  const [formData, setFormData] = useState({
    full_name: '',
    phone_number: '',
    email: '',
    password: '',
    role: 'sales' as UserRole
  })

  useEffect(() => {
    fetchStaff()
  }, [])

  const fetchStaff = async () => {
    try {
      setLoading(true)
      const { data, error } = await supabase.from('staff_profiles').select('*').order('created_at', { ascending: false })
      if (error) throw error
      setStaff(data || [])
    } catch (error) {
      console.error('Error fetching staff:', error)
      toast.error('Failed to fetch staff.')
    } finally {
      setLoading(false)
    }
  }

  const handleCloseModal = () => {
    setShowModal(false)
    setEditingStaff(null)
    resetForm()
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const toastId = toast.loading(editingStaff ? 'Updating staff member...' : 'Creating staff member...');
    
    try {
      if (editingStaff) {
        const { error } = await supabase.from('staff_profiles').update({ full_name: formData.full_name, phone_number: formData.phone_number, role: formData.role }).eq('id', editingStaff.id)
        if (error) throw error
        toast.success('Staff member updated!', { id: toastId });
      } else {
        const { error } = await signUp(formData.email, formData.password, {
          full_name: formData.full_name,
          phone_number: formData.phone_number,
          role: formData.role,
          created_by: profile?.id
        })
        if (error) throw error
        toast.success('Staff member created. They will receive an email to verify their account.', { id: toastId });
      }

      handleCloseModal()
      fetchStaff()
    } catch (error: any) {
      toast.error(`Error: ${error.message}`, { id: toastId });
    }
  }

  const resetForm = () => {
    setFormData({ full_name: '', phone_number: '', email: '', password: '', role: 'sales' })
  }

  const handleEdit = (staffMember: StaffProfile) => {
    setEditingStaff(staffMember)
    setFormData({
      full_name: staffMember.full_name,
      phone_number: staffMember.phone_number,
      email: '', 
      password: '',
      role: staffMember.role
    })
    setShowModal(true)
  }

  const handleDelete = async (staffId: string) => {
    if (!window.confirm('Are you sure you want to delete this staff member? This will also delete their login account and cannot be undone.')) {
      return
    }

    const toastId = toast.loading('Deleting staff member...');
    try {
      const { error } = await supabase.rpc('delete_user_and_profile', { user_id_to_delete: staffId })
      if (error) throw error
      toast.success('Staff member deleted.', { id: toastId });
      fetchStaff()
    } catch (error: any) {
      toast.error(`Error: ${error.message}`, { id: toastId });
    }
  }

  const columns = useMemo<ColumnDef<StaffProfile>[]>(() => [
    {
      accessorKey: 'full_name',
      header: 'Staff Member',
      cell: ({ row }) => (
        <div className="flex items-center">
          <div className="h-10 w-10 rounded-full bg-gray-100 flex items-center justify-center"><User className="h-6 w-6 text-gray-400" /></div>
          <div className="ml-4">
            <div className="text-sm font-medium text-gray-900">{row.original.full_name}</div>
          </div>
        </div>
      )
    },
    {
      accessorKey: 'phone_number',
      header: 'Contact',
    },
    {
      accessorKey: 'role',
      header: 'Role',
      cell: ({ row }) => (
        <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full capitalize ${
          row.original.role === 'owner' ? 'bg-purple-100 text-purple-800' :
          row.original.role === 'manager' ? 'bg-indigo-100 text-indigo-800' :
          'bg-green-100 text-green-800'
        }`}>
          {row.original.role}
        </span>
      )
    },
    {
      accessorKey: 'created_at',
      header: 'Date Joined',
      cell: ({ row }) => <div className="text-sm text-gray-500">{format(new Date(row.original.created_at), 'PP')}</div>
    },
    {
      id: 'actions',
      header: 'Actions',
      cell: ({ row }) => (
        <div className="flex space-x-2">
          <button onClick={() => handleEdit(row.original)} className="text-indigo-600 hover:text-indigo-900 p-1"><Edit className="h-4 w-4" /></button>
          {row.original.id !== profile?.id && <button onClick={() => handleDelete(row.original.id)} className="text-red-600 hover:text-red-900 p-1"><Trash2 className="h-4 w-4" /></button>}
        </div>
      )
    }
  ], [profile])

  if (loading) {
    return <div className="flex items-center justify-center h-64"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div></div>
  }

  return (
    <div className="space-y-6">
      <div className="sm:flex sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Staff Management</h1>
          <p className="mt-1 text-sm text-gray-500">Manage staff accounts and permissions</p>
        </div>
        <div className="mt-4 sm:mt-0">
          <button onClick={() => setShowModal(true)} className="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
            <Plus className="h-4 w-4 mr-2" /> Add Staff Member
          </button>
        </div>
      </div>

      <DataTable columns={columns} data={staff} />

      <Modal isOpen={showModal} onClose={handleCloseModal} title={editingStaff ? 'Edit Staff Member' : 'Add New Staff Member'}>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700">Full Name</label>
            <input type="text" required className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.full_name} onChange={(e) => setFormData(prev => ({ ...prev, full_name: e.target.value }))} />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700">Phone Number</label>
            <input type="tel" required className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.phone_number} onChange={(e) => setFormData(prev => ({ ...prev, phone_number: e.target.value }))} />
          </div>
          {!editingStaff && (
            <>
              <div>
                <label className="block text-sm font-medium text-gray-700">Email</label>
                <input type="email" required className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.email} onChange={(e) => setFormData(prev => ({ ...prev, email: e.target.value }))} />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700">Password</label>
                <input type="password" required minLength={6} className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.password} onChange={(e) => setFormData(prev => ({ ...prev, password: e.target.value }))} />
              </div>
            </>
          )}
          <div>
            <label className="block text-sm font-medium text-gray-700">Role</label>
            <select required className="mt-1 block w-full border border-gray-300 rounded-md px-3 py-2 focus:outline-none focus:ring-blue-500 focus:border-blue-500" value={formData.role} onChange={(e) => setFormData(prev => ({ ...prev, role: e.target.value as UserRole }))}>
              <option value="sales">Sales</option>
              <option value="manager">Manager</option>
              <option value="owner">Owner</option>
            </select>
          </div>
          <div className="flex justify-end space-x-3 pt-4">
            <button type="button" onClick={handleCloseModal} className="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">Cancel</button>
            <button type="submit" className="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">{editingStaff ? 'Update' : 'Create'} Staff Member</button>
          </div>
        </form>
      </Modal>
    </div>
  )
}
