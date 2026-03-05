// Politik Server - Client-side JavaScript

document.addEventListener('DOMContentLoaded', function() {
    // Select all checkbox for sync page
    const selectAll = document.getElementById('selectAll');
    if (selectAll) {
        selectAll.addEventListener('change', function() {
            const checkboxes = document.querySelectorAll('input[name="sessionIds[]"]');
            checkboxes.forEach(cb => cb.checked = selectAll.checked);
        });
    }

    // Highlight active nav link
    const currentPath = window.location.pathname;
    document.querySelectorAll('.nav-link').forEach(link => {
        const href = link.getAttribute('href');
        if (href === currentPath || (href !== '/' && currentPath.startsWith(href))) {
            link.classList.add('active');
        }
    });
});
