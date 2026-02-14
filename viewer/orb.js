// Afterword Orb — canvas-based animated energy sphere
(function () {
  const canvas = document.getElementById('orb-canvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const W = canvas.width;
  const H = canvas.height;
  const cx = W / 2;
  const cy = H / 2;
  const R = 72; // orb radius

  let t = 0;
  const TWO_PI = Math.PI * 2;

  // Seeded random for deterministic particles
  function seededRng(seed) {
    let s = seed;
    return function () {
      s = (s * 16807 + 0) % 2147483647;
      return (s - 1) / 2147483646;
    };
  }

  function lerpColor(c1, c2, t) {
    const r = c1[0] + (c2[0] - c1[0]) * t;
    const g = c1[1] + (c2[1] - c1[1]) * t;
    const b = c1[2] + (c2[2] - c1[2]) * t;
    return [r, g, b];
  }

  function rgba(c, a) {
    return `rgba(${Math.round(c[0])},${Math.round(c[1])},${Math.round(c[2])},${a})`;
  }

  const cyan = [0, 229, 255];
  const purple = [170, 0, 255];
  const pink = [255, 68, 204];
  const deepBlue = [15, 40, 80];
  const white = [255, 255, 255];
  const paleBlue = [200, 240, 255];

  function drawOrb(time) {
    ctx.clearRect(0, 0, W, H);
    const breath = (Math.sin(time * 0.8) + 1) / 2;
    const orbit = (time * 0.15) % 1;
    const bs = 0.94 + breath * 0.06;

    // 1. Outer pink/purple halo
    const haloR = R * 1.8 * bs;
    const haloGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, haloR);
    haloGrad.addColorStop(0, rgba(purple, 0.10));
    haloGrad.addColorStop(0.45, rgba(pink, 0.05));
    haloGrad.addColorStop(1, 'transparent');
    ctx.fillStyle = haloGrad;
    ctx.fillRect(0, 0, W, H);

    // 2. Mid cyan glow ring
    const midR = R * 1.35 * bs;
    const midGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, midR);
    midGrad.addColorStop(0, rgba(cyan, 0.12));
    midGrad.addColorStop(0.5, rgba(deepBlue, 0.05));
    midGrad.addColorStop(1, 'transparent');
    ctx.fillStyle = midGrad;
    ctx.beginPath();
    ctx.arc(cx, cy, midR, 0, TWO_PI);
    ctx.fill();

    // 3. Light rays
    const rng = seededRng(77);
    for (let i = 0; i < 16; i++) {
      const angle = (i / 16) * TWO_PI + orbit * TWO_PI * 0.25;
      const spread = 0.03 + rng() * 0.025;
      const alpha = 0.03 + rng() * 0.02;
      const rayEnd = R * 0.85 + R * 0.5 * bs;

      ctx.beginPath();
      ctx.moveTo(
        cx + Math.cos(angle - spread) * R * 0.75,
        cy + Math.sin(angle - spread) * R * 0.75
      );
      ctx.lineTo(cx + Math.cos(angle) * rayEnd, cy + Math.sin(angle) * rayEnd);
      ctx.lineTo(
        cx + Math.cos(angle + spread) * R * 0.75,
        cy + Math.sin(angle + spread) * R * 0.75
      );
      ctx.closePath();
      ctx.fillStyle = rgba(cyan, alpha);
      ctx.fill();
    }

    // 4. Main orb body
    const bodyGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, R * bs);
    bodyGrad.addColorStop(0, 'rgba(1,10,20,1)');
    bodyGrad.addColorStop(0.55, 'rgba(6,32,64,1)');
    bodyGrad.addColorStop(1, 'rgba(0,128,192,1)');
    ctx.fillStyle = bodyGrad;
    ctx.beginPath();
    ctx.arc(cx, cy, R * bs, 0, TWO_PI);
    ctx.fill();

    // 5. Nebula swirls
    const sRng = seededRng(99);
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * TWO_PI + orbit * TWO_PI * 0.15 + sRng() * 0.5;
      const d = R * (0.25 + sRng() * 0.45) * bs;
      const sx = cx + Math.cos(a) * d;
      const sy = cy + Math.sin(a) * d;
      const sr = R * (0.15 + sRng() * 0.2);
      const sAlpha = 0.05 + sRng() * 0.04;

      ctx.save();
      ctx.translate(sx, sy);
      ctx.rotate(a);
      ctx.scale(1.8, 1);
      const sGrad = ctx.createRadialGradient(0, 0, 0, 0, 0, sr);
      sGrad.addColorStop(0, rgba([16, 144, 221], sAlpha));
      sGrad.addColorStop(1, 'transparent');
      ctx.fillStyle = sGrad;
      ctx.beginPath();
      ctx.arc(0, 0, sr, 0, TWO_PI);
      ctx.fill();
      ctx.restore();
    }

    // 6. Luminous core
    const coreR = R * (0.22 + breath * 0.06);
    const coreGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, coreR);
    coreGrad.addColorStop(0, rgba(white, 0.95));
    coreGrad.addColorStop(0.25, rgba([144, 228, 255], 0.65));
    coreGrad.addColorStop(0.6, rgba(cyan, 0.12));
    coreGrad.addColorStop(1, 'transparent');
    ctx.fillStyle = coreGrad;
    ctx.beginPath();
    ctx.arc(cx, cy, coreR, 0, TWO_PI);
    ctx.fill();

    // 7. Orbiting wisps
    const wRng = seededRng(42);
    for (let i = 0; i < 12; i++) {
      const a = (i / 12) * TWO_PI + orbit * TWO_PI + wRng() * 0.4;
      const d = R * (0.45 + wRng() * 0.40) * bs;
      const wx = cx + Math.cos(a) * d;
      const wy = cy + Math.sin(a) * d;
      const wr = R * (0.05 + wRng() * 0.08);
      const wAlpha = 0.12 + wRng() * 0.18;

      const wGrad = ctx.createRadialGradient(wx, wy, 0, wx, wy, wr);
      wGrad.addColorStop(0, rgba(cyan, wAlpha));
      wGrad.addColorStop(1, 'transparent');
      ctx.fillStyle = wGrad;
      ctx.beginPath();
      ctx.arc(wx, wy, wr, 0, TWO_PI);
      ctx.fill();
    }

    // 8. Particle ring
    const pRng = seededRng(123);
    for (let i = 0; i < 28; i++) {
      const a = (i / 28) * TWO_PI + orbit * TWO_PI * 0.6;
      const d = R * (0.75 + pRng() * 0.35) * bs;
      const px = cx + Math.cos(a) * d;
      const py = cy + Math.sin(a) * d;
      const pr = 0.8 + pRng() * 1.8;
      const pAlpha = 0.12 + pRng() * 0.30;
      const pc = lerpColor(cyan, purple, pRng());

      // Glow
      ctx.fillStyle = rgba(pc, pAlpha * 0.15);
      ctx.beginPath();
      ctx.arc(px, py, pr * 2.5, 0, TWO_PI);
      ctx.fill();
      // Core
      ctx.fillStyle = rgba(pc, pAlpha);
      ctx.beginPath();
      ctx.arc(px, py, pr, 0, TWO_PI);
      ctx.fill();
    }

    // 9. Specular highlight
    const specX = cx - R * 0.20;
    const specY = cy - R * 0.26;
    const specGrad = ctx.createRadialGradient(specX, specY, 0, specX, specY, R * 0.28);
    specGrad.addColorStop(0, rgba(white, 0.20));
    specGrad.addColorStop(1, 'transparent');
    ctx.fillStyle = specGrad;
    ctx.beginPath();
    ctx.arc(specX, specY, R * 0.28, 0, TWO_PI);
    ctx.fill();

    // 10. Rim light (sweep)
    ctx.save();
    ctx.beginPath();
    ctx.arc(cx, cy, R * bs, 0, TWO_PI);
    ctx.lineWidth = 1.2;
    const rimGrad = ctx.createConicGradient(orbit * TWO_PI, cx, cy);
    rimGrad.addColorStop(0, rgba(cyan, 0));
    rimGrad.addColorStop(0.25, rgba(cyan, 0.18));
    rimGrad.addColorStop(0.65, rgba(deepBlue, 0.06));
    rimGrad.addColorStop(1, rgba(cyan, 0));
    ctx.strokeStyle = rimGrad;
    ctx.stroke();
    ctx.restore();

    // 11. Counter-rotating rim
    ctx.save();
    ctx.beginPath();
    ctx.arc(cx, cy, R * bs * 0.98, 0, TWO_PI);
    ctx.lineWidth = 0.8;
    const rimGrad2 = ctx.createConicGradient(-orbit * TWO_PI * 0.7, cx, cy);
    rimGrad2.addColorStop(0, rgba(paleBlue, 0));
    rimGrad2.addColorStop(0.5, rgba(paleBlue, 0.08));
    rimGrad2.addColorStop(1, rgba(paleBlue, 0));
    ctx.strokeStyle = rimGrad2;
    ctx.stroke();
    ctx.restore();
  }

  // "Signal Verified" pulse animation
  let verifiedPhase = 0;
  let showVerified = false;
  let verifiedTimer = null;

  function pulseVerified() {
    showVerified = true;
    verifiedPhase = 0;
    const label = document.getElementById('orb-label');
    if (label) {
      label.textContent = 'SIGNAL VERIFIED';
      label.style.opacity = '1';
    }
    clearTimeout(verifiedTimer);
    verifiedTimer = setTimeout(function () {
      if (label) label.style.opacity = '0';
      showVerified = false;
    }, 2800);
  }

  // Trigger verified on successful unlock
  const origSetStatus = window.setStatus;
  if (typeof origSetStatus === 'undefined') {
    // setStatus hasn't loaded yet, we'll patch it after app.js loads
    window._orbPulseVerified = pulseVerified;
  }

  function frame(ts) {
    t = ts / 1000;
    drawOrb(t);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);

  // Expose for app.js to call
  window._orbPulseVerified = pulseVerified;
})();
