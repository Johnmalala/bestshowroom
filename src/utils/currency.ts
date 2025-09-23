export const formatKES = (amount: number): string => {
  return new Intl.NumberFormat('en-KE', {
    style: 'currency',
    currency: 'KES',
    minimumFractionDigits: 0,
    maximumFractionDigits: 2
  }).format(amount)
}

export const parseKES = (value: string): number => {
  return parseFloat(value.replace(/[^\d.-]/g, '')) || 0
}
