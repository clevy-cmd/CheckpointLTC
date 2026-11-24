(() => {
  document.documentElement.classList.add("js");
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const grid = document.querySelector(".grid");
  let drift = 0;
  const tick = () => {
    drift = (drift + 0.12) % 160;
    grid.style.setProperty("--drift", `${drift}px`);
    requestAnimationFrame(tick);
  };
  if (!reduced) requestAnimationFrame(tick);

  const toc = document.querySelector(".guide-grid .toc");
  const list = toc.querySelector(".toc-list");
  const toggle = toc.querySelector(".toc-toggle");
  const setOpen = (open) => {
    toc.classList.toggle("open", open);
    toggle.setAttribute("aria-expanded", String(open));
  };
  toggle.addEventListener("click", () => setOpen(!toc.classList.contains("open")));
  list.addEventListener("click", (event) => {
    if (event.target.closest("a")) setOpen(false);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && toc.classList.contains("open")) {
      setOpen(false);
      toggle.focus();
    }
  });

  const links = new Map([...list.querySelectorAll("a")].map((a) => [a.getAttribute("href").slice(1), a]));
  const targets = [...document.querySelectorAll(".guide-body .part-head[id], .guide-body .topic[id]")];
  let current = null;
  const mark = () => {
    let found = targets[0];
    for (const target of targets) if (target.getBoundingClientRect().top < window.innerHeight * 0.3) found = target;
    const inBody = targets[0].getBoundingClientRect().top < window.innerHeight * 0.3;
    const key = inBody ? found.id : "";
    if (key === current) return;
    current = key;
    for (const [id, link] of links) link.classList.toggle("on", inBody && id === found.id);
    const active = links.get(found.id);
    const label = active ? active.textContent.replace(/^\d · /, "") : "Contents";
    toggle.textContent = inBody ? label : "Contents";
    if (active && getComputedStyle(toc).overflowY === "auto") {
      const top = active.offsetTop - toc.clientHeight / 2;
      toc.scrollTo({ top, behavior: reduced ? "auto" : "smooth" });
    }
  };
  let pending = false;
  window.addEventListener("scroll", () => {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => { pending = false; mark(); });
  }, { passive: true });
  mark();
})();

document.querySelectorAll(".menu").forEach((menu) => {
  menu.querySelectorAll("a").forEach((a) => a.addEventListener("click", () => menu.removeAttribute("open")));
  document.addEventListener("click", (e) => { if (menu.open && !menu.contains(e.target)) menu.removeAttribute("open"); });
});
