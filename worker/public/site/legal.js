(() => {
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const grid = document.querySelector(".grid");
  let drift = 0;
  const tick = () => {
    drift = (drift + 0.12) % 160;
    grid.style.setProperty("--drift", `${drift}px`);
    requestAnimationFrame(tick);
  };
  if (!reduced) requestAnimationFrame(tick);

  const links = new Map([...document.querySelectorAll(".toc a")].map((a) => [a.getAttribute("href").slice(1), a]));
  const headings = [...document.querySelectorAll(".doc-body h2[id]")];
  const mark = () => {
    let current = headings[0];
    for (const heading of headings) if (heading.getBoundingClientRect().top < window.innerHeight * 0.35) current = heading;
    for (const [id, link] of links) link.classList.toggle("on", current && id === current.id);
  };
  window.addEventListener("scroll", mark, { passive: true });
  mark();
})();

document.querySelectorAll(".menu").forEach((menu) => {
  menu.querySelectorAll("a").forEach((a) => a.addEventListener("click", () => menu.removeAttribute("open")));
  document.addEventListener("click", (e) => { if (menu.open && !menu.contains(e.target)) menu.removeAttribute("open"); });
});
