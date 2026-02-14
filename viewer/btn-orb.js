// Button Orb — hold-to-unlock animated energy orb
(function () {
  const canvas = document.getElementById('btn-orb-canvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const W = canvas.width;
  const H = canvas.height;
  const cx = W / 2;
  const cy = H / 2;
  const R = 68;
  const TWO_PI = Math.PI * 2;

  let t = 0;
  let holdProgress = 0; // 0..1
  let isHolding = false;
  let holdStart = 0;
  const HOLD_MS = 1800;
  let completed = false;
  let completedAt = 0;
  let flashPhase = 0;
  let disabled = false;
  let holdConsumed = false;

  // Energy release particles spawned on completion
  const releaseParticles = [];

  function rgba(c, a) {
    return 'rgba(' + Math.round(c[0]) + ',' + Math.round(c[1]) + ',' + Math.round(c[2]) + ',' + a + ')';
  }
  function lerp(a, b, t) { return a + (b - a) * t; }
  function lerpC(c1, c2, t) {
    return [lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t)];
  }

  const gold = [212, 168, 75];
  const amber = [247, 178, 74];
  const warmWhite = [255, 240, 210];
  const deepBrown = [30, 18, 4];
  const darkGold = [100, 70, 20];

  function seededRng(seed) {
    let s = seed;
    return function () {
      s = (s * 16807 + 0) % 2147483647;
      return (s - 1) / 2147483646;
    };
  }

  function spawnRelease() {
    for (let i = 0; i < 32; i++) {
      const angle = (i / 32) * TWO_PI + Math.random() * 0.3;
      releaseParticles.push({
        x: cx + Math.cos(angle) * R * 0.9,
        y: cy + Math.sin(angle) * R * 0.9,
        vx: Math.cos(angle) * (1.5 + Math.random() * 3),
        vy: Math.sin(angle) * (1.5 + Math.random() * 3),
        life: 1.0,
        r: 1.2 + Math.random() * 2.5,
        color: Math.random() > 0.5 ? gold : amber,
      });
    }
  }

  function drawOrb(time) {
    ctx.clearRect(0, 0, W, H);
    const breath = (Math.sin(time * 0.8) + 1) / 2;
    const orbit = (time * 0.12) % 1;
    const bs = 0.95 + breath * 0.05;
    const hp = holdProgress;

    // 1. Outer warm halo — grows with hold
    const haloR = R * (1.6 + hp * 0.5) * bs;
    const haloGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, haloR);
    haloGrad.addColorStop(0, rgba(gold, 0.06 + hp * 0.15));
    haloGrad.addColorStop(0.5, rgba(amber, 0.03 + hp * 0.06));
    haloGrad.addColorStop(1, 'transparent');
    ctx.fillStyle = haloGrad;
    ctx.fillRect(0, 0, W, H);

    // 2. Light rays — appear more on hold
    if (hp > 0.05) {
      const rng = seededRng(77);
      const rayCount = 14;
      for (let i = 0; i < rayCount; i++) {
        const angle = (i / rayCount) * TWO_PI + orbit * TWO_PI * 0.25;
        const spread = 0.025 + rng() * 0.02;
        const alpha = (0.02 + hp * 0.12) * (0.5 + rng() * 0.5);
        const rayEnd = R * 0.85 + R * hp * 1.2;
        ctx.beginPath();
        ctx.moveTo(cx + Math.cos(angle - spread) * R * 0.75, cy + Math.sin(angle - spread) * R * 0.75);
        ctx.lineTo(cx + Math.cos(angle) * rayEnd, cy + Math.sin(angle) * rayEnd);
        ctx.lineTo(cx + Math.cos(angle + spread) * R * 0.75, cy + Math.sin(angle + spread) * R * 0.75);
        ctx.closePath();
        ctx.fillStyle = rgba(gold, alpha);
        ctx.fill();
      }
    }

    // 3. Outer flames — always present, intensify on hold
    const fRng = seededRng(333);
    for (let i = 0; i < 12; i++) {
      const angle = (i / 12) * TWO_PI + orbit * TWO_PI * 0.2 + fRng() * 0.3;
      const len = R * (0.15 + fRng() * 0.25 + hp * 0.3 + breath * 0.06);
      const startD = R * (0.88 + fRng() * 0.1) * bs;
      const sx = cx + Math.cos(angle) * startD;
      const sy = cy + Math.sin(angle) * startD;
      const ex = sx + Math.cos(angle) * len;
      const ey = sy + Math.sin(angle) * len;
      const w = 2.5 + fRng() * 3.5 + hp * 3;
      const alpha = (0.05 + fRng() * 0.08 + hp * 0.12);

      // Glow
      const mx = (sx + ex) / 2, my = (sy + ey) / 2;
      ctx.fillStyle = rgba(amber, alpha * 0.25);
      ctx.beginPath();
      ctx.arc(mx, my, w * 2.5, 0, TWO_PI);
      ctx.fill();

      // Flame triangle
      const px = -Math.sin(angle) * w * 0.5;
      const py = Math.cos(angle) * w * 0.5;
      ctx.beginPath();
      ctx.moveTo(sx + px, sy + py);
      ctx.lineTo(ex, ey);
      ctx.lineTo(sx - px, sy - py);
      ctx.closePath();
      ctx.fillStyle = rgba(gold, alpha);
      ctx.fill();
    }

    // 4. Main orb body
    const bodyGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, R * bs);
    bodyGrad.addColorStop(0, rgba(deepBrown, 1));
    bodyGrad.addColorStop(0.5, rgba(darkGold, 1));
    bodyGrad.addColorStop(1, rgba(gold, 1));
    ctx.fillStyle = bodyGrad;
    ctx.beginPath();
    ctx.arc(cx, cy, R * bs, 0, TWO_PI);
    ctx.fill();

    // 5. Nebula swirls inside
    const sRng = seededRng(99);
    for (let i = 0; i < 5; i++) {
      const a = (i / 5) * TWO_PI + orbit * TWO_PI * 0.15 + sRng() * 0.5;
      const d = R * (0.25 + sRng() * 0.4) * bs;
      const sx2 = cx + Math.cos(a) * d;
      const sy2 = cy + Math.sin(a) * d;
      const sr = R * (0.12 + sRng() * 0.15);
      const sAlpha = 0.04 + sRng() * 0.03 + hp * 0.05;
      ctx.save();
      ctx.translate(sx2, sy2);
      ctx.rotate(a);
      ctx.scale(1.6, 1);
      const sGrad = ctx.createRadialGradient(0, 0, 0, 0, 0, sr);
      sGrad.addColorStop(0, rgba(amber, sAlpha));
      sGrad.addColorStop(1, 'transparent');
      ctx.fillStyle = sGrad;
      ctx.beginPath();
      ctx.arc(0, 0, sr, 0, TWO_PI);
      ctx.fill();
      ctx.restore();
    }

    // 6. Luminous core — grows dramatically on hold
    const coreR = R * (0.18 + breath * 0.04 + hp * 0.35);
    const coreGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, coreR);
    coreGrad.addColorStop(0, rgba(warmWhite, 0.95));
    coreGrad.addColorStop(0.3, rgba([255, 210, 140], 0.6 + hp * 0.3));
    coreGrad.addColorStop(0.65, rgba(gold, 0.1));
    coreGrad.addColorStop(1, 'transparent');
    ctx.fillStyle = coreGrad;
    ctx.beginPath();
    ctx.arc(cx, cy, coreR, 0, TWO_PI);
    ctx.fill();

    // 7. Orbital wisps
    const wRng = seededRng(42);
    for (let i = 0; i < 10; i++) {
      const a = (i / 10) * TWO_PI + orbit * TWO_PI + wRng() * 0.4;
      const d = R * (0.45 + wRng() * 0.35) * bs;
      const wx = cx + Math.cos(a) * d;
      const wy = cy + Math.sin(a) * d;
      const wr = R * (0.04 + wRng() * 0.06 + hp * 0.04);
      const wAlpha = 0.10 + wRng() * 0.15 + hp * 0.2;
      const wGrad = ctx.createRadialGradient(wx, wy, 0, wx, wy, wr);
      wGrad.addColorStop(0, rgba(amber, wAlpha));
      wGrad.addColorStop(1, 'transparent');
      ctx.fillStyle = wGrad;
      ctx.beginPath();
      ctx.arc(wx, wy, wr, 0, TWO_PI);
      ctx.fill();
    }

    // 8. Hold progress ring
    if (hp > 0.01 && !completed) {
      ctx.save();
      ctx.beginPath();
      ctx.arc(cx, cy, R * bs + 4, -Math.PI / 2, -Math.PI / 2 + TWO_PI * hp);
      ctx.lineWidth = 3;
      ctx.strokeStyle = rgba(warmWhite, 0.6 + hp * 0.4);
      ctx.lineCap = 'round';
      ctx.stroke();
      ctx.restore();
    }

    // 9. Specular highlight
    const specX = cx - R * 0.20;
    const specY = cy - R * 0.26;
    const specGrad = ctx.createRadialGradient(specX, specY, 0, specX, specY, R * 0.26);
    specGrad.addColorStop(0, rgba([255,255,255], 0.18));
    specGrad.addColorStop(1, 'transparent');
    ctx.fillStyle = specGrad;
    ctx.beginPath();
    ctx.arc(specX, specY, R * 0.26, 0, TWO_PI);
    ctx.fill();

    // 10. Rim light
    ctx.save();
    ctx.beginPath();
    ctx.arc(cx, cy, R * bs, 0, TWO_PI);
    ctx.lineWidth = 1.2 + hp * 2;
    const rimGrad = ctx.createConicGradient(orbit * TWO_PI, cx, cy);
    rimGrad.addColorStop(0, rgba(gold, 0));
    rimGrad.addColorStop(0.25, rgba(gold, 0.15 + hp * 0.3));
    rimGrad.addColorStop(0.65, rgba(darkGold, 0.05));
    rimGrad.addColorStop(1, rgba(gold, 0));
    ctx.strokeStyle = rimGrad;
    ctx.stroke();
    ctx.restore();

    // 11. Flash on completion
    if (completed) {
      const elapsed = (Date.now() - completedAt) / 1000;
      flashPhase = Math.min(elapsed / 0.6, 1);
      const flashA = (1 - flashPhase) * 0.5;
      if (flashA > 0.005) {
        const flashR = R * (1.0 + flashPhase * 2.5);
        const flashGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, flashR);
        flashGrad.addColorStop(0, rgba(warmWhite, flashA));
        flashGrad.addColorStop(0.4, rgba(gold, flashA * 0.5));
        flashGrad.addColorStop(1, 'transparent');
        ctx.fillStyle = flashGrad;
        ctx.beginPath();
        ctx.arc(cx, cy, flashR, 0, TWO_PI);
        ctx.fill();
      }
    }

    // 12. Release particles
    for (let i = releaseParticles.length - 1; i >= 0; i--) {
      const p = releaseParticles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.vx *= 0.97;
      p.vy *= 0.97;
      p.life -= 0.015;
      if (p.life <= 0) {
        releaseParticles.splice(i, 1);
        continue;
      }
      const pa = p.life * 0.7;
      ctx.fillStyle = rgba(p.color, pa * 0.2);
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r * 3, 0, TWO_PI);
      ctx.fill();
      ctx.fillStyle = rgba(p.color, pa);
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, TWO_PI);
      ctx.fill();
    }
  }

  // Interaction
  const wrap = canvas.parentElement;
  const label = wrap.querySelector('.orb-btn-label');

  function startHold() {
    if (disabled || completed) return;
    isHolding = true;
    holdConsumed = false;
    holdStart = Date.now();
  }

  function endHold() {
    isHolding = false;
  }

  wrap.addEventListener('pointerdown', function (e) {
    e.preventDefault();
    startHold();
  });
  wrap.addEventListener('pointerup', endHold);
  wrap.addEventListener('pointerleave', endHold);
  wrap.addEventListener('pointercancel', endHold);

  // Expose for app.js
  window._btnOrb = {
    triggerUnlock: function () {
      // Called by app.js when vault unlocks successfully
      completed = true;
      completedAt = Date.now();
      spawnRelease();
      if (label) {
        label.textContent = 'SIGNAL VERIFIED';
        wrap.classList.add('verified');
      }
      if (typeof window._orbPulseVerified === 'function') window._orbPulseVerified();
      setTimeout(function () {
        completed = false;
        holdProgress = 0;
        if (label) {
          label.textContent = 'Hold to Check In';
          wrap.classList.remove('verified');
        }
      }, 3500);
    },
    isHoldComplete: function () {
      if (holdProgress >= 1.0 && !completed && !holdConsumed) {
        holdConsumed = true;
        return true;
      }
      return false;
    },
    setDisabled: function (v) {
      disabled = v;
      if (v) wrap.classList.add('disabled');
      else wrap.classList.remove('disabled');
    },
    getHoldProgress: function () {
      return holdProgress;
    }
  };

  function frame(ts) {
    t = ts / 1000;

    // Update hold progress
    if (isHolding && !completed) {
      const elapsed = Date.now() - holdStart;
      holdProgress = Math.min(elapsed / HOLD_MS, 1.0);
    } else if (!completed) {
      holdProgress = Math.max(holdProgress - 0.03, 0);
    }

    drawOrb(t);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
