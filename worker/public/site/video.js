(() => {
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const video = document.querySelector("video");
  const steps = [...document.querySelectorAll(".steps li")];
  const times = steps.map((li) => Number(li.querySelector("button").dataset.at));
  for (const li of steps) {
    li.querySelector("button").addEventListener("click", (event) => {
      video.currentTime = Number(event.currentTarget.dataset.at);
      video.play().catch(() => {});
      video.scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "center" });
    });
  }
  video.addEventListener("timeupdate", () => {
    let current = -1;
    times.forEach((time, index) => { if (video.currentTime >= time - 0.25) current = index; });
    steps.forEach((li, index) => {
      li.classList.toggle("now", index === current);
      li.classList.toggle("past", index < current);
    });
  });
})();

document.querySelectorAll(".menu").forEach((menu) => {
  menu.querySelectorAll("a").forEach((a) => a.addEventListener("click", () => menu.removeAttribute("open")));
  document.addEventListener("click", (e) => { if (menu.open && !menu.contains(e.target)) menu.removeAttribute("open"); });
});
