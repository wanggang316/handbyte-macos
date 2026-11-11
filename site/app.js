// Copy install command on click.
document.querySelectorAll('.cmd[data-copy]').forEach((btn) => {
  btn.addEventListener('click', async () => {
    const text = btn.querySelector('.cmd__text')?.textContent?.trim();
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
    }
    btn.classList.add('is-copied');
    clearTimeout(btn._t);
    btn._t = setTimeout(() => btn.classList.remove('is-copied'), 1600);
  });
});

