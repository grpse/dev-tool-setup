/* Read-only browser audit. Run after the embedded font has loaded. Returns
   positioning errors in the original 2443 × 1374 reference coordinates. */
(() => {
  const scene = document.querySelector('.scene').getBoundingClientRect();
  const scaleX = scene.width / 2443, scaleY = scene.height / 1374;
  const labels = [...document.querySelectorAll('.registered-legend')].map(element => {
    const target = JSON.parse(element.dataset.target);
    const ink = JSON.parse(element.dataset.metrics || 'null');
    if (!ink) throw new Error(`Unmeasured label: ${element.dataset.text}`);
    const key = element.closest('button');
    const rect = element.getBoundingClientRect();
    const probe = element.querySelector('i').getBoundingClientRect();
    const [sx, sy] = element.dataset.scale.split(',').map(Number);
    const fontScale = Number(getComputedStyle(element).fontSize.replace('px', '')) / target.fontSize;
    const dx = (rect.left - ink.left * fontScale * sx - scene.left) / scaleX - (542 + Number(key.dataset.keyX) + target.x);
    const dy = (probe.top - ink.ascent * fontScale * sy - scene.top) / scaleY - (390 + Number(key.dataset.keyY) + target.y);
    return { key: key.dataset.keyId, text: element.dataset.text, dx, dy };
  });
  return {
    count: labels.length,
    maxSourcePixelPositionError: Math.max(...labels.flatMap(label => [Math.abs(label.dx), Math.abs(label.dy)])),
    labels
  };
})();
