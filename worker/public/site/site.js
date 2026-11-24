(() => {
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const finePointer = window.matchMedia("(pointer: fine)").matches;
  const NS = "http://www.w3.org/2000/svg";

  const grid = document.querySelector(".grid");
  const main = document.querySelector("main");
  const svg = main.querySelector(".track");
  const road = svg.querySelector(".road");
  const lit = svg.querySelector(".lit");
  const padHolder = svg.querySelector(".pads");
  const runner = svg.querySelector(".runner");
  const sections = [...main.querySelectorAll(":scope > section")];
  const shots = [...document.querySelectorAll(".shot, .code-card")].map((el) => ({ el, depth: Number(el.dataset.depth) || 0, rot: el.dataset.rot || "0deg" }));
  for (const shot of shots) shot.el.style.setProperty("--rot", shot.rot);

  let samples = [];
  let total = 0;
  let pads = [];
  let mainTop = 0;
  let shown = 0;
  let drift = 0;
  let mouseX = 0;
  let mouseY = 0;
  let tiltX = 0;
  let tiltY = 0;

  const lengthAtY = (y) => {
    if (!samples.length) return 0;
    if (y <= samples[0].y) return 0;
    if (y >= samples[samples.length - 1].y) return total;
    let low = 0;
    let high = samples.length - 1;
    while (high - low > 1) {
      const mid = (low + high) >> 1;
      if (samples[mid].y < y) low = mid;
      else high = mid;
    }
    const a = samples[low];
    const b = samples[high];
    const t = b.y === a.y ? 0 : (y - a.y) / (b.y - a.y);
    return a.len + (b.len - a.len) * t;
  };

  const build = () => {
    const width = main.clientWidth;
    const height = main.offsetHeight;
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
    mainTop = main.getBoundingClientRect().top + window.scrollY;
    const pad = parseFloat(getComputedStyle(sections[0]).paddingLeft) || 30;
    const edge = Math.max(0, (width - 1240) / 2);
    const xs = { l: edge + pad / 2, r: width - edge - pad / 2 };
    const anchors = [];
    let d = "";
    sections.forEach((section, index) => {
      const top = section.offsetTop;
      const x = xs[section.dataset.side] ?? xs.l;
      const heading = section.querySelector("h1, h2");
      const padY = top + (heading ? heading.offsetTop + Math.min(heading.offsetHeight / 2, 34) : 60);
      if (index === 0) d = `M ${x} ${top + 30}`;
      anchors.push({ x, y: padY, end: index === sections.length - 1 });
      const next = sections[index + 1];
      if (next) {
        const nextX = xs[next.dataset.side] ?? xs.l;
        const nextTop = next.offsetTop;
        const room = parseFloat(getComputedStyle(next).paddingTop) || 120;
        const y1 = nextTop + 6;
        const y2 = nextTop + Math.min(110, room - 24);
        const bend = (y2 - y1) * 0.62;
        d += ` L ${x} ${y1} C ${x} ${y1 + bend} ${nextX} ${y2 - bend} ${nextX} ${y2}`;
      } else {
        d += ` L ${x} ${top + section.offsetHeight - 70}`;
      }
    });
    road.setAttribute("d", d);
    lit.setAttribute("d", d);
    total = road.getTotalLength();
    lit.style.strokeDasharray = `${total} ${total}`;
    samples = [];
    for (let len = 0; len <= total; len += 6) samples.push({ len, y: road.getPointAtLength(len).y });
    samples.push({ len: total, y: road.getPointAtLength(total).y });
    padHolder.replaceChildren();
    pads = anchors.map((anchor) => {
      const el = document.createElementNS(NS, "rect");
      el.setAttribute("x", String(anchor.x - 8));
      el.setAttribute("y", String(anchor.y - 8));
      el.setAttribute("width", "16");
      el.setAttribute("height", "16");
      if (anchor.end) el.classList.add("end");
      padHolder.append(el);
      return { el, len: lengthAtY(anchor.y) };
    });
    shown = Math.min(shown, total);
  };

  const place = () => {
    lit.style.strokeDashoffset = String(total - shown);
    const p = road.getPointAtLength(shown);
    const q = road.getPointAtLength(Math.min(total, shown + 2));
    const angle = (Math.atan2(q.y - p.y, q.x - p.x) * 180) / Math.PI;
    runner.setAttribute("transform", `translate(${p.x} ${p.y}) rotate(${angle + 45})`);
    for (const pad of pads) pad.el.classList.toggle("on", shown >= pad.len - 4);
  };

  const frame = () => {
    if (!reduced) {
      drift = (drift + 0.12) % 160;
      grid.style.setProperty("--drift", `${drift}px`);
    }
    const atBottom = window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 4;
    const target = atBottom ? total : lengthAtY(window.scrollY - mainTop + window.innerHeight * 0.62);
    const step = reduced ? target - shown : (target - shown) * 0.075;
    if (Math.abs(target - shown) > 0.2) {
      shown += step;
      place();
    }
    tiltX += (mouseX - tiltX) * 0.06;
    tiltY += (mouseY - tiltY) * 0.06;
    if (!reduced) {
      const middle = window.innerHeight / 2;
      for (const shot of shots) {
        const box = shot.el.getBoundingClientRect();
        if (box.bottom < -100 || box.top > window.innerHeight + 100) continue;
        const offset = (box.top + box.height / 2 - middle) * -shot.depth;
        const lean = finePointer ? ` perspective(1400px) rotateX(${(-tiltY * 3).toFixed(2)}deg) rotateY(${(tiltX * 4).toFixed(2)}deg)` : "";
        shot.el.style.transform = `translate3d(0, ${offset.toFixed(1)}px, 0)${lean} rotate(${shot.rot})`;
      }
    }
    requestAnimationFrame(frame);
  };

  if (finePointer) {
    window.addEventListener("pointermove", (event) => {
      mouseX = event.clientX / window.innerWidth - 0.5;
      mouseY = event.clientY / window.innerHeight - 0.5;
    }, { passive: true });
  }

  let pending = false;
  const rebuild = () => {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => { pending = false; build(); place(); });
  };
  new ResizeObserver(rebuild).observe(main);
  window.addEventListener("resize", rebuild);
  if (document.fonts) document.fonts.ready.then(rebuild);
  build();
  shown = lengthAtY(window.scrollY - mainTop + window.innerHeight * 0.62);
  place();
  requestAnimationFrame(frame);

  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) if (entry.isIntersecting) entry.target.classList.add("in");
    },
    { threshold: 0, rootMargin: "0px 0px -18% 0px" },
  );
  for (const section of sections) observer.observe(section);

  const live = document.querySelector(".live");
  if (live) {
    const rows = [...live.querySelectorAll("li")];
    const count = live.querySelector(".live-count");
    const who = live.querySelector(".live-who");
    const names = ["Maya", "Devon", "Kai", "Jordan", "Sam"];
    let step = 0;
    const paint = () => {
      const done = rows.filter((row) => row.classList.contains("done")).length;
      count.textContent = `${done} of ${rows.length}`;
      live.style.setProperty("--done", `${(done / rows.length) * 100}%`);
    };
    const advance = () => {
      if (step < rows.length) {
        rows[step].classList.add("done");
        who.innerHTML = "";
        who.append(Object.assign(document.createElement("b"), { textContent: names[step] }), " checked off a task");
        step += 1;
      } else {
        rows.forEach((row) => row.classList.remove("done"));
        who.textContent = "New sprint, fresh list";
        step = 0;
      }
      paint();
    };
    paint();
    if (!reduced) setInterval(advance, 2600);
    else {
      rows.slice(0, 3).forEach((row) => row.classList.add("done"));
      paint();
    }
  }

  const chat = document.querySelector(".chat");
  if (chat) {
    const feed = chat.querySelector(".chat-feed");
    const typing = chat.querySelector(".chat-typing");
    const typingName = typing.querySelector("span");
    const channelLabel = chat.querySelector(".chat-channel");
    const channels = [...chat.querySelectorAll(".chat-side span")];
    const colors = { Dev: "#29b9e8", Kai: "#c0283b", Jordan: "#8b6fd6", Sam: "#e8833a", Riley: "#3ba55d" };
    const lines = [
      ["announcements", "Dev", "Version 1.0.0 is live! TODO scanning, player reports and a brand new guide 🎉"],
      ["help", "Kai", "how do I link a task to a script line?"],
      ["help", "Dev", "Select the script, open the task and press Link my selection. Or write a TODO comment and scan 👍"],
      ["ideas", "Jordan", "could tasks have little checklists inside them?"],
      ["ideas", "Dev", "Ooh, good one. Adding it to my list"],
      ["sneakpeeks", "Dev", "Sneak peeks of what I'm working on next always land here first 👀"],
      ["help", "Sam", "can my whole team share one list?"],
      ["help", "Dev", "Yep! Open People and press Add a person with their username or UserId"],
      ["help", "Riley", "just set it up for my studio, where do I start?"],
      ["help", "Dev", "Try the Game launch checklist template, then check the guide. Ask here anytime"],
    ];
    const node = (tag, className, text) => {
      const el = document.createElement(tag);
      if (className) el.className = className;
      if (text) el.textContent = text;
      return el;
    };
    const message = ([channel, who, text]) => {
      const avatar = node("span", "av", who[0]);
      avatar.style.background = colors[who] ?? "#5b606a";
      const head = node("div");
      head.append(node("span", "who", who));
      if (who === "Dev") head.append(node("span", "badge", "CREATOR"));
      head.append(node("span", "where", `#${channel}`));
      const body = node("div");
      body.append(head, node("p", "", text));
      const row = node("div", "msg");
      row.append(avatar, body);
      return row;
    };
    const focus = (channel) => {
      for (const item of channels) item.classList.toggle("on", item.dataset.ch === channel);
      channelLabel.textContent = `# ${channel}`;
    };

    if (reduced) {
      for (const line of lines.slice(0, 4)) feed.append(message(line));
      focus(lines[3][0]);
    } else {
      let index = 0;
      let visible = false;
      let started = false;
      const post = () => {
        if (!visible) {
          setTimeout(post, 800);
          return;
        }
        const line = lines[index % lines.length];
        index += 1;
        focus(line[0]);
        feed.append(message(line));
        while (feed.children.length > 4) feed.firstElementChild.remove();
        const used = () => [...feed.children].reduce((total, child) => total + child.offsetHeight + 16, 6);
        while (feed.children.length > 1 && used() > feed.clientHeight) feed.firstElementChild.remove();
        const next = lines[index % lines.length];
        setTimeout(() => {
          typingName.textContent = `${next[1]} is typing`;
          typing.classList.add("show");
        }, 1500);
        setTimeout(() => {
          typing.classList.remove("show");
          post();
        }, 3700);
      };
      new IntersectionObserver((entries) => {
        visible = entries.some((entry) => entry.isIntersecting);
        if (visible && !started) {
          started = true;
          post();
        }
      }, { threshold: 0.2 }).observe(chat);
    }
  }

  const track = document.querySelector(".track-imgs");
  if (track) {
    track.append(...[...track.children].map((img) => img.cloneNode(true)));
    new IntersectionObserver((entries, watcher) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      for (const img of track.querySelectorAll("img")) img.loading = "eager";
      watcher.disconnect();
    }, { rootMargin: "800px 0px" }).observe(track);
  }

  const app = document.getElementById("app");
  if (!app) return;
  const $ = (selector) => app.querySelector(selector);
  const make = (tag, props = {}, children = []) => {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(props)) {
      if (key === "class") el.className = value;
      else if (key === "text") el.textContent = value;
      else if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
      else el.setAttribute(key, value);
    }
    for (const child of children) el.append(child);
    return el;
  };

  let nextId = 100;
  const task = (text, extra = {}) => ({ id: nextId++, text, done: false, label: null, priority: 0, due: null, notes: "", section: null, ...extra });
  const fresh = () => [
    {
      id: 1,
      title: "Spawn Lobby Update",
      tasks: [
        task("Full playtest with a fresh account", { label: "Scripting", priority: 3, due: "Due tomorrow", section: "Gameplay", notes: "Use an alt so no saved data carries over." }),
        task("Check every badge and game pass", { label: "UI", priority: 2, section: "Gameplay" }),
        task("Balance pass on rewards", { done: true, section: "Gameplay" }),
        task("Thumbnail and icon", { label: "UI", due: "Due Thursday", section: "Polish" }),
        task("Game description and tags", { done: true, section: "Polish" }),
        task("Fix lobby door not opening on mobile", { label: "Bug", priority: 3, section: "Polish" }),
        task("Sparkle trail on the spawn pad", { label: "VFX", section: "Polish" }),
      ],
    },
    {
      id: 2,
      title: "Bug Triage",
      tasks: [task("Reproduce the bug"), task("Find the cause"), task("Write the fix"), task("Test it in a live server")],
    },
  ];

  let state = { lists: fresh(), current: 1, view: "list", filter: null, open: null };
  const list = () => state.lists.find((l) => l.id === state.current);

  const toast = (text, action) => {
    const box = $(".toasts");
    const node = make("div", { class: "toast" }, [make("span", { text })]);
    if (action) node.append(make("button", { text: action.label, onclick: () => { action.run(); node.remove(); } }));
    box.append(node);
    while (box.children.length > 2) box.firstChild.remove();
    setTimeout(() => node.remove(), action ? 5000 : 2600);
  };

  const renderSidebar = () => {
    const holder = $(".lists");
    holder.replaceChildren(
      ...state.lists.map((l) => {
        const done = l.tasks.filter((t) => t.done).length;
        return make("button", { class: l.id === state.current ? "on" : "", onclick: () => { state.current = l.id; state.open = null; state.filter = null; app.classList.remove("lists-open"); render(); } }, [
          make("span", { text: l.title }),
          make("small", { text: `${done}/${l.tasks.length}` }),
        ]);
      }),
    );
  };

  const taskRow = (t, draggable) => {
    const meta = make("div", { class: "meta" });
    if (t.label) meta.append(make("span", { class: `tag ${t.label}`, text: t.label }));
    if (t.priority) meta.append(make("span", { class: "prio", text: ["", "! Low", "!! Medium", "!!! High"][t.priority] }));
    if (t.due) meta.append(make("span", { class: "due", text: t.due }));
    const row = make("div", { class: `task${t.done ? " done" : ""}${state.open === t.id ? " open" : ""}`, draggable: draggable ? "true" : "false" }, [
      make("span", { class: "handle", text: "⋮⋮", title: "Drag to reorder" }),
      make("span", { class: "box", text: t.done ? "✓" : "", role: "checkbox", "aria-checked": String(t.done), onclick: (event) => { event.stopPropagation(); t.done = !t.done; render(); } }),
      make("div", { class: "task-text" }, [make("p", { text: t.text }), meta]),
    ]);
    row.addEventListener("click", () => { state.open = state.open === t.id ? null : t.id; render(); });
    row.addEventListener("dragstart", (event) => { event.dataTransfer.setData("text/plain", String(t.id)); row.classList.add("dragging"); });
    row.addEventListener("dragend", () => row.classList.remove("dragging"));
    row.addEventListener("dragover", (event) => { event.preventDefault(); row.classList.add("over"); });
    row.addEventListener("dragleave", () => row.classList.remove("over"));
    row.addEventListener("drop", (event) => {
      event.preventDefault();
      event.stopPropagation();
      row.classList.remove("over");
      const moving = list().tasks.find((x) => x.id === Number(event.dataTransfer.getData("text/plain")));
      if (!moving || moving === t) return;
      const tasks = list().tasks;
      tasks.splice(tasks.indexOf(moving), 1);
      tasks.splice(tasks.indexOf(t), 0, moving);
      moving.section = t.section;
      if (state.view === "board") moving.done = t.done;
      render();
    });
    return row;
  };

  const renderTasks = () => {
    const l = list();
    const shown = l.tasks.filter((t) => !state.filter || t.label === state.filter);
    const holder = $(".tasks");
    if (state.view === "board") {
      const column = (title, done) => {
        const col = make("div", { class: "column" }, [make("h4", { text: title })]);
        for (const t of shown.filter((x) => x.done === done)) col.append(taskRow(t, true));
        col.addEventListener("dragover", (event) => { event.preventDefault(); col.classList.add("over"); });
        col.addEventListener("dragleave", () => col.classList.remove("over"));
        col.addEventListener("drop", (event) => {
          event.preventDefault();
          col.classList.remove("over");
          const moving = l.tasks.find((x) => x.id === Number(event.dataTransfer.getData("text/plain")));
          if (moving) { moving.done = done; render(); }
        });
        return col;
      };
      holder.replaceChildren(make("div", { class: "board" }, [column("To do", false), column("Done", true)]));
      return;
    }
    const nodes = [];
    let section;
    for (const t of shown) {
      if (t.section !== section) {
        section = t.section;
        if (section) nodes.push(make("p", { class: "section-title", text: section }));
      }
      nodes.push(taskRow(t, true));
    }
    if (!nodes.length) nodes.push(make("p", { class: "section-title", text: shown.length ? "" : "Nothing here yet. Add a task below." }));
    holder.replaceChildren(...nodes);
  };

  const renderDrawer = () => {
    const drawer = $(".drawer");
    const t = list().tasks.find((x) => x.id === state.open);
    drawer.classList.toggle("open", Boolean(t));
    drawer.setAttribute("aria-hidden", t ? "false" : "true");
    if (!t) return;
    const chipRow = (values, current, apply) =>
      make("div", { class: "row" }, values.map(([text, value]) => make("button", { class: `chip${current === value ? " on" : ""}`, text, onclick: () => { apply(value); render(); } })));
    const notes = make("textarea", { placeholder: "Add notes", "aria-label": "Notes" });
    notes.value = t.notes;
    notes.addEventListener("input", () => { t.notes = notes.value; });
    drawer.replaceChildren(
      make("button", { class: "icon close", text: "✕", "aria-label": "Close", onclick: () => { state.open = null; render(); } }),
      make("p", { class: "list-title", text: t.text }),
      make("button", { class: "done-btn", text: t.done ? "Done ✓" : "Mark done", onclick: () => { t.done = !t.done; render(); } }),
      make("h5", { text: "Priority" }),
      chipRow([["None", 0], ["Low", 1], ["Medium", 2], ["High", 3]], t.priority, (v) => { t.priority = v; }),
      make("h5", { text: "Label" }),
      chipRow([["None", null], ["Scripting", "Scripting"], ["UI", "UI"], ["VFX", "VFX"], ["Bug", "Bug"]], t.label, (v) => { t.label = v; }),
      make("h5", { text: "Due" }),
      chipRow([["None", null], ["Today", "Due today"], ["Tomorrow", "Due tomorrow"], ["Next week", "Due next week"]], t.due, (v) => { t.due = v; }),
      make("h5", { text: "Notes" }),
      notes,
      make("button", { class: "delete", text: "Delete task", onclick: () => removeTask(t) }),
    );
  };

  const removeTask = (t) => {
    const tasks = list().tasks;
    const index = tasks.indexOf(t);
    tasks.splice(index, 1);
    state.open = null;
    render();
    const owner = list();
    toast("Task moved to the trash.", { label: "Undo", run: () => { owner.tasks.splice(index, 0, t); render(); } });
  };

  const render = () => {
    const l = list();
    const done = l.tasks.filter((t) => t.done).length;
    $(".list-title").textContent = l.title;
    $(".list-meta").textContent = `Owner · ${done} of ${l.tasks.length} done`;
    $(".progress span").style.width = `${l.tasks.length ? (done / l.tasks.length) * 100 : 0}%`;
    $('[data-act="board"]').classList.toggle("on", state.view === "board");
    const chips = $(".chips");
    chips.replaceChildren(
      ...[["All", null], ["Scripting", "Scripting"], ["UI", "UI"], ["VFX", "VFX"], ["Bug", "Bug"]].map(([text, value]) =>
        make("button", { class: `chip${state.filter === value ? " on" : ""}`, text, onclick: () => { state.filter = value; render(); } }),
      ),
    );
    renderSidebar();
    renderTasks();
    renderDrawer();
    const scrim = app.querySelector(".scrim");
    if (app.classList.contains("lists-open") && !scrim) {
      $(".body").append(make("div", { class: "scrim", onclick: () => { app.classList.remove("lists-open"); render(); } }));
    } else if (!app.classList.contains("lists-open") && scrim) scrim.remove();
  };

  const composer = $(".composer");
  const input = composer.querySelector("input");
  const count = composer.querySelector(".count");
  input.addEventListener("input", () => { count.textContent = input.value.length >= 192 ? `${input.value.length} / 240` : ""; });
  composer.addEventListener("submit", (event) => {
    event.preventDefault();
    const text = input.value.trim();
    if (!text) return;
    list().tasks.push(task(text, { label: state.filter, section: list().tasks.at(-1)?.section ?? null }));
    input.value = "";
    count.textContent = "";
    render();
    $(".tasks").scrollTop = 1e6;
  });

  const palette = $(".palette");
  const paletteInput = palette.querySelector("input");
  const results = palette.querySelector(".results");
  let selected = 0;
  const commands = () => [
    ...state.lists.map((l) => ({ title: l.title, kind: "List", run: () => { state.current = l.id; state.open = null; } })),
    ...list().tasks.map((t) => ({ title: t.text, kind: "Task", run: () => { state.open = t.id; } })),
    { title: state.view === "board" ? "Switch to list view" : "Switch to board view", kind: "View", run: () => { state.view = state.view === "board" ? "list" : "board"; } },
    { title: "New list", kind: "Action", run: () => newList() },
    { title: "Reset the demo", kind: "Action", run: () => reset() },
  ];
  const showResults = () => {
    const query = paletteInput.value.toLowerCase();
    const matches = commands().filter((c) => c.title.toLowerCase().includes(query)).slice(0, 7);
    selected = Math.min(selected, Math.max(0, matches.length - 1));
    results.replaceChildren(
      ...matches.map((c, index) =>
        make("button", { class: index === selected ? "on" : "", onclick: () => { closePalette(); c.run(); render(); } }, [make("span", { text: c.title }), make("small", { text: c.kind })]),
      ),
    );
    return matches;
  };
  const openPalette = () => { palette.hidden = false; paletteInput.value = ""; selected = 0; showResults(); setTimeout(() => paletteInput.focus(), 0); };
  const closePalette = () => { palette.hidden = true; app.focus({ preventScroll: true }); };
  paletteInput.addEventListener("input", () => { selected = 0; showResults(); });
  paletteInput.addEventListener("keydown", (event) => {
    const matches = showResults();
    if (event.key === "ArrowDown") { selected = Math.min(matches.length - 1, selected + 1); showResults(); event.preventDefault(); }
    else if (event.key === "ArrowUp") { selected = Math.max(0, selected - 1); showResults(); event.preventDefault(); }
    else if (event.key === "Enter" && matches[selected]) { closePalette(); matches[selected].run(); render(); }
    else if (event.key === "Escape") closePalette();
  });

  let hovering = false;
  app.addEventListener("mouseenter", () => { hovering = true; });
  app.addEventListener("mouseleave", () => { hovering = false; });
  document.addEventListener("keydown", (event) => {
    const typing = ["INPUT", "TEXTAREA"].includes(document.activeElement?.tagName);
    if (event.key === "/" && !typing && (hovering || app.contains(document.activeElement))) {
      event.preventDefault();
      openPalette();
    } else if (event.key === "Escape" && !palette.hidden) closePalette();
    else if (event.key === "Escape" && state.open) { state.open = null; render(); }
  });

  const newList = () => {
    const id = nextId++;
    state.lists.push({ id, title: `New list ${state.lists.length + 1}`, tasks: [] });
    state.current = id;
    state.open = null;
    toast("List created. Add a task below.");
    setTimeout(() => input.focus({ preventScroll: true }), 50);
  };
  const reset = () => {
    state = { lists: fresh(), current: 1, view: "list", filter: null, open: null };
    toast("Demo reset.");
  };

  app.addEventListener("click", (event) => {
    const act = event.target.closest("[data-act]")?.dataset.act;
    if (!act) return;
    if (act === "board") state.view = state.view === "board" ? "list" : "board";
    if (act === "command") { openPalette(); return; }
    if (act === "reset") reset();
    if (act === "newlist") newList();
    if (act === "sidebar") app.classList.toggle("lists-open");
    render();
  });

  render();
})();

document.querySelectorAll(".menu").forEach((menu) => {
  menu.querySelectorAll("a").forEach((a) => a.addEventListener("click", () => menu.removeAttribute("open")));
  document.addEventListener("click", (e) => { if (menu.open && !menu.contains(e.target)) menu.removeAttribute("open"); });
});
