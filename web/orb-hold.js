// Canvas orb for the "Hold to check in" button on afterword-app.com
(function () {
  var canvas = document.querySelector('.orb-hold__canvas');
  if (!canvas) return;
  var ctx = canvas.getContext('2d');
  var W = canvas.width, H = canvas.height;
  var cx = W / 2, cy = H / 2, R = W * 0.34;

  var t = 0;
  var holdProgress = 0;
  var isHolding = false;
  var holdStart = 0;
  var HOLD_MS = 1100;
  var completed = false;
  var completedAt = 0;
  var flashPhase = 0;

  var releaseParticles = [];

  function rgba(c, a) {
    return 'rgba(' + Math.round(c[0]) + ',' + Math.round(c[1]) + ',' + Math.round(c[2]) + ',' + a + ')';
  }
  function lerp(a, b, t) { return a + (b - a) * t; }
  function lerpC(c1, c2, t) {
    return [lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t)];
  }

  // Color palette — warm gold/amber
  var gold = [242, 180, 100];
  var amber = [241, 139, 78];
  var cream = [255, 240, 210];
  var teal = [91, 192, 180];
  var white = [255, 255, 255];

  function spawnRelease() {
    for (var i = 0; i < 28; i++) {
      var angle = Math.random() * Math.PI * 2;
      var speed = 1.2 + Math.random() * 3.5;
      releaseParticles.push({
        x: cx + Math.cos(angle) * R * 0.5,
        y: cy + Math.sin(angle) * R * 0.5,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        life: 1,
        decay: 0.008 + Math.random() * 0.012,
        size: 2 + Math.random() * 4,
        color: Math.random() > 0.5 ? gold : teal
      });
    }
  }

  function draw() {
    t += 0.016;
    ctx.clearRect(0, 0, W, H);

    if (isHolding && !completed) {
      holdProgress = Math.min(1, (performance.now() - holdStart) / HOLD_MS);
      if (holdProgress >= 1) {
        completed = true;
        completedAt = t;
        flashPhase = 1;
        spawnRelease();
        var wrap = canvas.closest('.orb-hold');
        var label = wrap && wrap.querySelector('.orb-hold__label');
        if (wrap) wrap.classList.add('is-success');
        if (label) label.textContent = 'Signal Verified';
        setTimeout(function () {
          completed = false;
          holdProgress = 0;
          flashPhase = 0;
          if (wrap) wrap.classList.remove('is-success');
          if (label) label.textContent = 'Hold to check in';
        }, 2400);
      }
    }

    var breath = Math.sin(t * 1.8) * 0.5 + 0.5;
    var bs = 1 + breath * 0.04;
    var r = R * bs;

    // Outer ambient glow
    var outerGlow = ctx.createRadialGradient(cx, cy, r * 0.6, cx, cy, r * 1.6);
    outerGlow.addColorStop(0, rgba(gold, 0.06 + holdProgress * 0.08));
    outerGlow.addColorStop(0.5, rgba(amber, 0.03 + holdProgress * 0.04));
    outerGlow.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = outerGlow;
    ctx.beginPath();
    ctx.arc(cx, cy, r * 1.6, 0, Math.PI * 2);
    ctx.fill();

    // Nebula layer — soft colored clouds
    for (var n = 0; n < 3; n++) {
      var na = t * 0.3 + n * 2.1;
      var nd = r * (0.2 + n * 0.12);
      var nx = cx + Math.cos(na) * nd;
      var ny = cy + Math.sin(na) * nd;
      var ng = ctx.createRadialGradient(nx, ny, 0, nx, ny, r * 0.5);
      var nc = n === 0 ? gold : n === 1 ? amber : teal;
      ng.addColorStop(0, rgba(nc, 0.08 + holdProgress * 0.06));
      ng.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = ng;
      ctx.beginPath();
      ctx.arc(nx, ny, r * 0.5, 0, Math.PI * 2);
      ctx.fill();
    }

    // Progress ring
    if (holdProgress > 0 && !completed) {
      ctx.beginPath();
      ctx.arc(cx, cy, r + 6, -Math.PI / 2, -Math.PI / 2 + holdProgress * Math.PI * 2);
      ctx.strokeStyle = rgba(gold, 0.85);
      ctx.lineWidth = 4;
      ctx.lineCap = 'round';
      ctx.stroke();
    }

    // Outer ring
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.strokeStyle = rgba(gold, 0.18 + breath * 0.08 + holdProgress * 0.15);
    ctx.lineWidth = 2;
    ctx.stroke();

    // Flame wisps around the ring
    for (var f = 0; f < 10; f++) {
      var fa = (f / 10) * Math.PI * 2 + t * 0.6;
      var fLen = r * (0.12 + Math.sin(t * 3 + f * 1.7) * 0.06) * (1 + holdProgress * 0.5);
      var fx1 = cx + Math.cos(fa) * r;
      var fy1 = cy + Math.sin(fa) * r;
      var fx2 = cx + Math.cos(fa) * (r + fLen);
      var fy2 = cy + Math.sin(fa) * (r + fLen);
      var fg = ctx.createLinearGradient(fx1, fy1, fx2, fy2);
      fg.addColorStop(0, rgba(gold, 0.3 + holdProgress * 0.2));
      fg.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.beginPath();
      ctx.moveTo(fx1, fy1);
      ctx.lineTo(fx2, fy2);
      ctx.strokeStyle = fg;
      ctx.lineWidth = 2 + Math.sin(t * 4 + f) * 1;
      ctx.stroke();
    }

    // Orbital wisps
    for (var w = 0; w < 5; w++) {
      var wa = t * (0.4 + w * 0.15) + w * 1.25;
      var wd = r * (0.55 + Math.sin(t * 2 + w) * 0.15);
      var wx = cx + Math.cos(wa) * wd;
      var wy = cy + Math.sin(wa) * wd;
      var ws = 3 + Math.sin(t * 3 + w * 2) * 1.5;
      ctx.beginPath();
      ctx.arc(wx, wy, ws, 0, Math.PI * 2);
      ctx.fillStyle = rgba(cream, 0.12 + holdProgress * 0.1);
      ctx.fill();
    }

    // Core gradient
    var coreG = ctx.createRadialGradient(cx - r * 0.15, cy - r * 0.15, 0, cx, cy, r * 0.85);
    if (completed) {
      coreG.addColorStop(0, rgba(white, 0.95));
      coreG.addColorStop(0.3, rgba(teal, 0.8));
      coreG.addColorStop(0.7, rgba(teal, 0.35));
      coreG.addColorStop(1, 'rgba(0,0,0,0)');
    } else {
      coreG.addColorStop(0, rgba(cream, 0.65 + holdProgress * 0.2));
      coreG.addColorStop(0.35, rgba(gold, 0.45 + holdProgress * 0.15));
      coreG.addColorStop(0.7, rgba(amber, 0.15 + holdProgress * 0.1));
      coreG.addColorStop(1, 'rgba(0,0,0,0)');
    }
    ctx.fillStyle = coreG;
    ctx.beginPath();
    ctx.arc(cx, cy, r * 0.85, 0, Math.PI * 2);
    ctx.fill();

    // Inner bright core
    var innerG = ctx.createRadialGradient(cx, cy, 0, cx, cy, r * 0.25);
    if (completed) {
      innerG.addColorStop(0, rgba(white, 0.9));
      innerG.addColorStop(1, rgba(teal, 0.2));
    } else {
      innerG.addColorStop(0, rgba(cream, 0.5 + holdProgress * 0.3));
      innerG.addColorStop(1, rgba(gold, 0.1));
    }
    ctx.fillStyle = innerG;
    ctx.beginPath();
    ctx.arc(cx, cy, r * 0.25, 0, Math.PI * 2);
    ctx.fill();

    // Specular highlight
    var specG = ctx.createRadialGradient(cx - r * 0.22, cy - r * 0.25, 0, cx - r * 0.22, cy - r * 0.25, r * 0.35);
    specG.addColorStop(0, rgba(white, 0.18 + holdProgress * 0.1));
    specG.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = specG;
    ctx.beginPath();
    ctx.arc(cx - r * 0.22, cy - r * 0.25, r * 0.35, 0, Math.PI * 2);
    ctx.fill();

    // Flash burst on completion
    if (flashPhase > 0) {
      flashPhase = Math.max(0, flashPhase - 0.02);
      var flashR = r * (1 + (1 - flashPhase) * 1.2);
      var flashG = ctx.createRadialGradient(cx, cy, 0, cx, cy, flashR);
      flashG.addColorStop(0, rgba(white, flashPhase * 0.5));
      flashG.addColorStop(0.5, rgba(teal, flashPhase * 0.3));
      flashG.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = flashG;
      ctx.beginPath();
      ctx.arc(cx, cy, flashR, 0, Math.PI * 2);
      ctx.fill();
    }

    // Release particles
    for (var p = releaseParticles.length - 1; p >= 0; p--) {
      var pt = releaseParticles[p];
      pt.x += pt.vx;
      pt.y += pt.vy;
      pt.vx *= 0.98;
      pt.vy *= 0.98;
      pt.life -= pt.decay;
      if (pt.life <= 0) {
        releaseParticles.splice(p, 1);
        continue;
      }
      ctx.beginPath();
      ctx.arc(pt.x, pt.y, pt.size * pt.life, 0, Math.PI * 2);
      ctx.fillStyle = rgba(pt.color, pt.life * 0.7);
      ctx.fill();
    }

    requestAnimationFrame(draw);
  }

  // Interaction
  var wrap = canvas.closest('.orb-hold');

  function startHold() {
    if (completed) return;
    isHolding = true;
    holdStart = performance.now();
  }

  function endHold() {
    if (!isHolding) return;
    isHolding = false;
    if (!completed) {
      holdProgress = 0;
    }
  }

  wrap.addEventListener('pointerdown', function (e) {
    e.preventDefault();
    startHold();
  });
  wrap.addEventListener('pointerup', endHold);
  wrap.addEventListener('pointercancel', endHold);
  wrap.addEventListener('pointerleave', endHold);

  draw();
})();
