/**
 * Dark mode toggle for PipeCD docs (pattern from dark-theme-editor).
 * Persists preference in localStorage and syncs data-theme on html.
 * Overrides Chroma inline syntax colors in dark mode for readable code blocks.
 */
(function () {
  var KEY = 'pipecd-docs-theme';
  var DARK_CODE_COLOR = '#e6edf3';

  function getTheme() {
    return document.documentElement.getAttribute('data-theme') || 'light';
  }

  function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    try {
      localStorage.setItem(KEY, theme);
    } catch (e) {}
    applyCodeBlockColors(theme);
  }

  function applyCodeBlockColors(theme) {
    var selector = '.td-content pre *, .td-content .highlight *';
    var nodes = document.querySelectorAll(selector);
    if (theme === 'dark') {
      nodes.forEach(function (el) {
        el.style.setProperty('color', DARK_CODE_COLOR, 'important');
      });
    } else {
      nodes.forEach(function (el) {
        el.style.removeProperty('color');
      });
    }
  }

  function toggleTheme() {
    var next = getTheme() === 'dark' ? 'light' : 'dark';
    setTheme(next);
  }

  window.__setTheme = setTheme;

  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('.theme-toggle').forEach(function (btn) {
      btn.addEventListener('click', toggleTheme);
    });
    applyCodeBlockColors(getTheme());
  });
})();
