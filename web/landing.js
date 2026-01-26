const revealItems = document.querySelectorAll(".reveal");

if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.15 }
  );

  revealItems.forEach((item) => observer.observe(item));
} else {
  revealItems.forEach((item) => item.classList.add("is-visible"));
}

const header = document.querySelector("[data-header]");
const menuToggle = document.querySelector("[data-menu-toggle]");

if (header && menuToggle) {
  const setOpen = (isOpen) => {
    header.classList.toggle("is-open", isOpen);
    menuToggle.setAttribute("aria-expanded", String(isOpen));
    menuToggle.setAttribute("aria-label", isOpen ? "Close menu" : "Open menu");
  };

  const closeMenu = () => setOpen(false);
  const toggleMenu = () => setOpen(!header.classList.contains("is-open"));

  menuToggle.addEventListener("click", (event) => {
    event.preventDefault();
    toggleMenu();
  });

  header.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (target.closest(".nav a") || target.closest(".header-actions a")) {
      closeMenu();
    }
  });

  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (!header.contains(target)) {
      closeMenu();
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeMenu();
  });

  const mq = window.matchMedia("(min-width: 960px)");
  const handleMq = () => {
    if (mq.matches) closeMenu();
  };

  handleMq();
  mq.addEventListener("change", handleMq);
}

const holdButton = document.querySelector("[data-hold]");
const holdLabel = document.querySelector("[data-hold-label]");

if (holdButton && holdLabel) {
  const holdMs = 1100;
  let rafId = null;
  let startAt = 0;
  let isPointerDown = false;
  let didComplete = false;

  const setProgress = (progress) => {
    const clamped = Math.max(0, Math.min(1, progress));
    holdButton.style.setProperty("--hold-progress", String(clamped));
  };

  const reset = () => {
    didComplete = false;
    holdButton.classList.remove("is-holding", "is-success");
    holdLabel.textContent = "Hold to check in";
    setProgress(0);
  };

  const complete = () => {
    didComplete = true;
    holdButton.classList.remove("is-holding");
    holdButton.classList.add("is-success");
    holdLabel.textContent = "Checked in";
    setProgress(1);
    window.setTimeout(reset, 1800);
  };

  const tick = (now) => {
    if (!isPointerDown || didComplete) return;
    const elapsed = now - startAt;
    const progress = elapsed / holdMs;
    setProgress(progress);
    if (elapsed >= holdMs) {
      complete();
      return;
    }
    rafId = window.requestAnimationFrame(tick);
  };

  const startHold = () => {
    if (didComplete) return;
    isPointerDown = true;
    holdButton.classList.add("is-holding");
    startAt = performance.now();
    if (rafId) window.cancelAnimationFrame(rafId);
    rafId = window.requestAnimationFrame(tick);
  };

  const endHold = () => {
    if (!isPointerDown) return;
    isPointerDown = false;
    if (!didComplete) {
      holdButton.classList.remove("is-holding");
      setProgress(0);
    }
    if (rafId) {
      window.cancelAnimationFrame(rafId);
      rafId = null;
    }
  };

  holdButton.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    holdButton.setPointerCapture?.(event.pointerId);
    startHold();
  });

  holdButton.addEventListener("pointerup", endHold);
  holdButton.addEventListener("pointercancel", endHold);
  holdButton.addEventListener("pointerleave", endHold);

  holdButton.addEventListener("keydown", (event) => {
    if (event.key === " " || event.key === "Enter") {
      event.preventDefault();
      startHold();
    }
  });

  holdButton.addEventListener("keyup", (event) => {
    if (event.key === " " || event.key === "Enter") {
      event.preventDefault();
      endHold();
    }
  });
}
