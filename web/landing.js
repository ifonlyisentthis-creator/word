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
