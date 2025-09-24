// Flattens a nested object for CSV export, creating dot-notation keys.
const flattenObject = (obj: any, parentKey = '', result: { [key: string]: any } = {}) => {
  for (const key in obj) {
    if (Object.prototype.hasOwnProperty.call(obj, key)) {
      const propName = parentKey ? `${parentKey}.${key}` : key;
      if (typeof obj[key] === 'object' && obj[key] !== null && !Array.isArray(obj[key])) {
        flattenObject(obj[key], propName, result);
      } else {
        result[propName] = obj[key];
      }
    }
  }
  return result;
};


export const exportToCSV = (data: any[], filename: string) => {
  if (!data || data.length === 0) {
    console.error("No data to export.");
    return;
  }

  // Flatten all rows to handle nested objects like `customer.full_name`
  const flattenedData = data.map(row => flattenObject(row));

  // Create a comprehensive header from all possible keys across all objects
  const headerSet = new Set<string>();
  flattenedData.forEach(row => {
    Object.keys(row).forEach(key => headerSet.add(key));
  });
  const header = Array.from(headerSet);

  const replacer = (value: any) => value === null ? '' : value;

  // Map each row to the comprehensive header order
  const csvRows = flattenedData.map(row =>
    header.map(fieldName => {
      // Ensure value is properly quoted and escaped
      const value = replacer(row[fieldName]);
      const stringValue = String(value);
      // If the string contains a comma, a quote, or a newline, wrap it in double quotes
      if (stringValue.includes(',') || stringValue.includes('"') || stringValue.includes('\n')) {
        // Escape existing double quotes by doubling them
        return `"${stringValue.replace(/"/g, '""')}"`;
      }
      return stringValue;
    }).join(',')
  );

  const csvString = [header.join(','), ...csvRows].join('\r\n');

  const blob = new Blob([csvString], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.setAttribute("href", url);
  link.setAttribute("download", `${filename}.csv`);
  link.style.visibility = 'hidden';
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
};
