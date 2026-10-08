(function() {
    const page = window.location.pathname.split('/').pop();
    const collapsibleIndexes = ['annotated.html', 'topics.html'];

    if (collapsibleIndexes.includes(page) && typeof dynsection !== 'undefined') {
        dynsection.toggleLevel(2);
    }
})();
