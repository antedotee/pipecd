/**
 * Copy Code Button Functionality
 * Adds a copy button to all code blocks with hover effects
 */
(function() {
    'use strict';

    function addCopyButtons() {
        // Find all code blocks (pre > code elements)
        const codeBlocks = document.querySelectorAll('pre > code, div.highlight > pre');
        
        codeBlocks.forEach(function(codeBlock) {
            // Get the parent pre or container element
            const pre = codeBlock.tagName === 'CODE' ? codeBlock.parentElement : codeBlock;
            
            // Skip if already has a copy button
            if (pre.parentElement.classList.contains('code-block-wrapper')) {
                return;
            }
            
            // Create wrapper div
            const wrapper = document.createElement('div');
            wrapper.className = 'code-block-wrapper';
            
            // Replace pre with wrapper in DOM
            pre.parentNode.insertBefore(wrapper, pre);
            wrapper.appendChild(pre);
            
            // Create copy button
            const copyButton = document.createElement('button');
            copyButton.className = 'copy-code-button';
            copyButton.setAttribute('aria-label', 'Copy code to clipboard');
            copyButton.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>';
            
            // Add click event
            copyButton.addEventListener('click', function(e) {
                e.preventDefault();
                copyCodeToClipboard(codeBlock, copyButton);
            });
            
            wrapper.appendChild(copyButton);
        });
    }
    
    function copyCodeToClipboard(codeElement, button) {
        // Get the code text
        let code = codeElement.textContent || codeElement.innerText;
        
        // Remove any line numbers if present
        code = code.replace(/^\s*\d+\s+/gm, '');
        
        // Use the Clipboard API
        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(code).then(function() {
                showCopySuccess(button);
            }).catch(function(err) {
                console.error('Failed to copy code: ', err);
                fallbackCopyTextToClipboard(code, button);
            });
        } else {
            // Fallback for older browsers
            fallbackCopyTextToClipboard(code, button);
        }
    }
    
    function fallbackCopyTextToClipboard(text, button) {
        const textArea = document.createElement('textarea');
        textArea.value = text;
        textArea.style.position = 'fixed';
        textArea.style.top = '0';
        textArea.style.left = '0';
        textArea.style.width = '2em';
        textArea.style.height = '2em';
        textArea.style.padding = '0';
        textArea.style.border = 'none';
        textArea.style.outline = 'none';
        textArea.style.boxShadow = 'none';
        textArea.style.background = 'transparent';
        
        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();
        
        try {
            const successful = document.execCommand('copy');
            if (successful) {
                showCopySuccess(button);
            }
        } catch (err) {
            console.error('Fallback: Failed to copy', err);
        }
        
        document.body.removeChild(textArea);
    }
    
    function showCopySuccess(button) {
        // Save original content
        const originalHTML = button.innerHTML;
        
        // Show success icon
        button.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>';
        button.classList.add('copied');
        
        // Reset after 2 seconds
        setTimeout(function() {
            button.innerHTML = originalHTML;
            button.classList.remove('copied');
        }, 2000);
    }
    
    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', addCopyButtons);
    } else {
        addCopyButtons();
    }
    
    // Also re-run if content is dynamically loaded
    // (useful for SPAs or dynamically loaded content)
    if (typeof MutationObserver !== 'undefined') {
        const observer = new MutationObserver(function(mutations) {
            let shouldRerun = false;
            mutations.forEach(function(mutation) {
                if (mutation.addedNodes.length) {
                    mutation.addedNodes.forEach(function(node) {
                        if (node.nodeType === 1 && (node.tagName === 'PRE' || node.querySelector('pre'))) {
                            shouldRerun = true;
                        }
                    });
                }
            });
            if (shouldRerun) {
                addCopyButtons();
            }
        });
        
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
    }
})();
