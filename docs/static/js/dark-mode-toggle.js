/**
 * Dark mode toggle for PipeCD docs (pattern from dark-theme-editor).
 * Persists preference in localStorage and syncs data-theme on html.
 * Overrides Chroma inline syntax colors in dark mode for readable code blocks.
 */
(function () {
  var KEY = 'pipecd-docs-theme';
  var DARK_CODE_COLOR = '#e6edf3';
  var CNCF_LOGO_WHITE = 'https://www.cncf.io/wp-content/uploads/2022/05/CNCF_logo_white.svg';
  var CNCF_LOGO_COLOR = 'https://www.cncf.io/wp-content/uploads/2022/07/cncf-color-bg.svg';

  function getTheme() {
    return document.documentElement.getAttribute('data-theme') || 'light';
  }

  function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    try {
      localStorage.setItem(KEY, theme);
    } catch (e) {
      // localStorage may throw in private mode or when quota exceeded
    }
    applyCodeBlockColors(theme);
    applyFooterLogo(theme);
  }

  function applyFooterLogo(theme) {
    var homeFooter = document.querySelector('.td-outer div.bg-white.d-print-none');
    if (!homeFooter) return;
    var img = homeFooter.querySelector('img[alt="cncf logo"]');
    if (!img) return;
    img.src = theme === 'dark' ? CNCF_LOGO_WHITE : CNCF_LOGO_COLOR;
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

  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('.theme-toggle').forEach(function (btn) {
      btn.addEventListener('click', toggleTheme);
    });
    applyCodeBlockColors(getTheme());
    applyFooterLogo(getTheme());
  });
})();
