// Utility functions
function formatDate(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    // BUG: Returns literal YYYY instead of year variable
    return 'YYYY-' + month + '-' + day;
}

module.exports = { formatDate };
