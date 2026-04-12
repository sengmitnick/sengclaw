// Simple Clipboard Utility
// Copy to clipboard with fallback support for iframe and older browsers

function copyToClipboard(text: string): Promise<boolean> {
  return new Promise<boolean>((resolve, reject) => {
    // Try modern Clipboard API first
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text)
        .then(() => resolve(true))
        .catch(() => {
          if (fallbackCopy(text)) {
            resolve(true);
          } else {
            reject(new Error('Copy failed'));
          }
        });
    } else {
      if (fallbackCopy(text)) {
        resolve(true);
      } else {
        reject(new Error('Copy failed'));
      }
    }
  });
}

function fallbackCopy(text: string): boolean {
  const textArea = document.createElement('textarea');
  textArea.value = text;
  textArea.style.position = 'fixed';
  textArea.style.opacity = '0';
  document.body.appendChild(textArea);
  textArea.select();

  try {
    const success = document.execCommand('copy');
    document.body.removeChild(textArea);
    return success;
  } catch (error) {
    document.body.removeChild(textArea);
    return false;
  }
}

// Export globally
window.copyToClipboard = copyToClipboard;

// Auto-init copy buttons on DOM ready
document.addEventListener('DOMContentLoaded', () => {
  window.initCopyButtons?.();
});
document.addEventListener('turbo:load', () => {
  window.initCopyButtons?.();
});

// Copy button handler for download section
window.initCopyButtons = function(): void {
  document.querySelectorAll('[data-copy-btn]').forEach(btn => {
    btn.addEventListener('click', async function(this: HTMLElement) {
      const targetId = this.getAttribute('data-target-id');
      const codeEl = targetId ? document.getElementById(targetId) : null;
      if (!codeEl) return;

      const text = codeEl.textContent || '';

      try {
        await window.copyToClipboard(text);
        // Success feedback
        const originalHTML = this.innerHTML;
        const originalBg = this.style.backgroundColor;
        this.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>';
        this.style.backgroundColor = 'rgba(34,197,94,0.3)';
        this.style.color = '#22c55e';
        this.style.borderColor = 'rgba(34,197,94,0.5)';
        this.style.transform = 'scale(1.1)';

        setTimeout(() => {
          this.innerHTML = originalHTML;
          this.style.backgroundColor = originalBg;
          this.style.color = '#F59E0B';
          this.style.borderColor = 'rgba(245,158,11,0.3)';
          this.style.transform = 'scale(1)';
        }, 2000);
      } catch (e) {
        // Error feedback
        this.style.backgroundColor = 'rgba(239,68,68,0.3)';
        this.style.color = '#ef4444';
        this.style.transform = 'shake 0.5s';
        setTimeout(() => {
          this.style.backgroundColor = 'rgba(245,158,11,0.15)';
          this.style.color = '#F59E0B';
          this.style.transform = 'scale(1)';
        }, 2000);
      }
    });
  });
};
