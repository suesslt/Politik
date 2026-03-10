// Politik Server – Client-side JavaScript

// HTMX loading bar
document.addEventListener('htmx:beforeRequest', function() {
    const bar = document.getElementById('loading-bar');
    if (bar) { bar.classList.add('active'); }
});
document.addEventListener('htmx:afterRequest', function() {
    const bar = document.getElementById('loading-bar');
    if (bar) {
        bar.classList.remove('active');
        bar.style.width = '100%';
        setTimeout(() => { bar.style.width = '0'; }, 300);
    }
});

// Select all checkbox for sync page
document.addEventListener('DOMContentLoaded', function() {
    const selectAll = document.getElementById('selectAll');
    if (selectAll) {
        selectAll.addEventListener('change', function() {
            const checkboxes = document.querySelectorAll('input.session-checkbox');
            checkboxes.forEach(cb => cb.checked = selectAll.checked);
        });
    }
});
