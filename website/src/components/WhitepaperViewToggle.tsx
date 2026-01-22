/**
 * WhitepaperViewToggle - Toggle between Professional and Interactive views
 */
import { useState, useEffect } from 'react';

export default function WhitepaperViewToggle() {
  const [isInteractive, setIsInteractive] = useState(false);

  // Apply/remove class to document for CSS-based demo visibility
  useEffect(() => {
    if (isInteractive) {
      document.documentElement.classList.add('interactive-mode');
      document.documentElement.classList.remove('professional-mode');
    } else {
      document.documentElement.classList.add('professional-mode');
      document.documentElement.classList.remove('interactive-mode');
    }
  }, [isInteractive]);

  // Set initial state from URL or localStorage
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const mode = params.get('mode') || localStorage.getItem('whitepaper-mode');
    if (mode === 'interactive') {
      setIsInteractive(true);
    }
  }, []);

  // Save preference
  useEffect(() => {
    localStorage.setItem('whitepaper-mode', isInteractive ? 'interactive' : 'professional');
  }, [isInteractive]);

  return (
    <div className="flex items-center gap-3 bg-bg-card border border-border rounded-full p-1">
      <button
        onClick={() => setIsInteractive(false)}
        className={`px-4 py-1.5 rounded-full text-sm font-medium transition-all ${
          !isInteractive
            ? 'bg-brand text-white'
            : 'text-text-muted hover:text-white'
        }`}
      >
        Professional
      </button>
      <button
        onClick={() => setIsInteractive(true)}
        className={`px-4 py-1.5 rounded-full text-sm font-medium transition-all ${
          isInteractive
            ? 'bg-brand text-white'
            : 'text-text-muted hover:text-white'
        }`}
      >
        Interactive
      </button>
    </div>
  );
}
