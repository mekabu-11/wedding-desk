(function () {
  "use strict";

  var body = document.body;
  var root = document.documentElement;
  var sidebarKey = "wedding-desk.sidebar-collapsed";
  var themeKey = "wedding-desk.theme";

  function read(key) {
    try {
      return window.localStorage.getItem(key);
    } catch (error) {
      return null;
    }
  }

  function write(key, value) {
    try {
      window.localStorage.setItem(key, value);
    } catch (error) {
      // Private browsing or blocked storage should not disable the controls.
    }
  }

  function setSidebarCollapsed(collapsed) {
    body.classList.toggle("sidebar-collapsed", collapsed);
    var button = document.querySelector("[data-sidebar-toggle]");
    if (!button) return;
    button.setAttribute("aria-expanded", String(!collapsed));
    button.setAttribute("aria-label", collapsed ? "サイドバーを展開する" : "サイドバーを折りたたむ");
    var icon = button.querySelector("span");
    if (icon) icon.textContent = collapsed ? "›" : "‹";
  }

  function setTheme(theme) {
    var dark = theme === "dark";
    root.dataset.theme = dark ? "dark" : "light";
    var button = document.querySelector("[data-theme-toggle]");
    if (!button) return;
    button.setAttribute("aria-pressed", String(dark));
    button.setAttribute("aria-label", dark ? "ライトテーマに切り替え" : "ブラックテーマに切り替え");
    var label = button.querySelector("[data-theme-label]");
    if (label) label.textContent = dark ? "ライトテーマ" : "ブラックテーマ";
    var icon = button.querySelector(".theme-toggle-icon");
    if (icon) icon.textContent = dark ? "☼" : "◐";
  }

  function isMobileViewport() {
    return window.matchMedia && window.matchMedia("(max-width: 760px)").matches;
  }

  function setMobileMenuOpen(open) {
    var toggle = document.querySelector("[data-mobile-menu-toggle]");
    var backdrop = document.querySelector("[data-mobile-menu-close]");
    if (!toggle) return;
    body.classList.toggle("mobile-menu-open", open);
    toggle.setAttribute("aria-expanded", String(open));
    toggle.setAttribute("aria-label", open ? "メニューを閉じる" : "メニューを開く");
    var icon = toggle.querySelector("span");
    if (icon) icon.textContent = open ? "×" : "☰";
    if (backdrop) backdrop.hidden = !open;
  }

  function applySidebarPreference() {
    var isMobile = isMobileViewport();
    setSidebarCollapsed(!isMobile && read(sidebarKey) === "1");
    if (!isMobile) setMobileMenuOpen(false);
  }

  applySidebarPreference();
  window.addEventListener("resize", applySidebarPreference);
  setTheme(read(themeKey) === "dark" ? "dark" : "light");

  var sidebarButton = document.querySelector("[data-sidebar-toggle]");
  if (sidebarButton) {
    sidebarButton.addEventListener("click", function () {
      var collapsed = !body.classList.contains("sidebar-collapsed");
      setSidebarCollapsed(collapsed);
      write(sidebarKey, collapsed ? "1" : "0");
    });
  }

  var mobileMenuButton = document.querySelector("[data-mobile-menu-toggle]");
  var mobileMenuBackdrop = document.querySelector("[data-mobile-menu-close]");
  if (mobileMenuButton) {
    mobileMenuButton.addEventListener("click", function () {
      setMobileMenuOpen(!body.classList.contains("mobile-menu-open"));
    });
  }
  if (mobileMenuBackdrop) mobileMenuBackdrop.addEventListener("click", function () { setMobileMenuOpen(false); });
  document.querySelectorAll("[data-mobile-nav] a").forEach(function (link) {
    link.addEventListener("click", function () { setMobileMenuOpen(false); });
  });
  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape" && body.classList.contains("mobile-menu-open")) setMobileMenuOpen(false);
  });

  var themeButton = document.querySelector("[data-theme-toggle]");
  if (themeButton) {
    themeButton.addEventListener("click", function () {
      var dark = root.dataset.theme !== "dark";
      setTheme(dark ? "dark" : "light");
      write(themeKey, dark ? "dark" : "light");
    });
  }

  var filterDialog = document.querySelector("[data-filter-dialog]");
  var filterOpenButton = document.querySelector("[data-filter-open]");
  var filterCloseButton = document.querySelector("[data-filter-close]");

  function closeFilterDialog() {
    if (!filterDialog) return;
    if (typeof filterDialog.close === "function") {
      filterDialog.close();
    } else {
      filterDialog.removeAttribute("open");
    }
    if (filterOpenButton) filterOpenButton.setAttribute("aria-expanded", "false");
  }

  if (filterDialog && filterOpenButton) {
    filterOpenButton.addEventListener("click", function () {
      if (typeof filterDialog.showModal === "function") {
        filterDialog.showModal();
      } else {
        filterDialog.setAttribute("open", "open");
      }
      filterOpenButton.setAttribute("aria-expanded", "true");
      var firstField = filterDialog.querySelector("select, input");
      if (firstField) firstField.focus();
    });

    if (filterCloseButton) filterCloseButton.addEventListener("click", closeFilterDialog);

    filterDialog.addEventListener("click", function (event) {
      if (event.target === filterDialog) closeFilterDialog();
    });
  }

  function parseDate(value) {
    if (!value) return null;
    var parts = value.split("-").map(Number);
    return new Date(Date.UTC(parts[0], parts[1] - 1, parts[2]));
  }

  function formatDate(date) {
    return date.toISOString().slice(0, 10);
  }

  function addDays(date, days) {
    var result = new Date(date.getTime());
    result.setUTCDate(result.getUTCDate() + days);
    return result;
  }

  function dayDifference(later, earlier) {
    return Math.round((later.getTime() - earlier.getTime()) / 86400000);
  }

  function setupGanttInteractions() {
    var boards = document.querySelectorAll("[data-gantt-board]");
    if (!boards.length) return;
    var csrf = document.querySelector("meta[name='csrf-token']");
    var dragging = null;

    boards.forEach(function (board) {
      var rangeStart = parseDate(board.dataset.rangeStart);
      var dayCount = Number(board.dataset.days || 0);
      var timelines = board.querySelectorAll(".gantt-row-timeline");

      board.querySelectorAll(".gantt-bar[draggable='true']").forEach(function (bar) {
        bar.addEventListener("dragstart", function (event) {
          dragging = {
            bar: bar,
            startsOn: parseDate(bar.dataset.ganttStartsOn),
            dueOn: parseDate(bar.dataset.ganttDueOn),
            lockVersion: bar.dataset.ganttLockVersion,
            dragged: false
          };
          bar.classList.add("dragging");
          event.dataTransfer.effectAllowed = "move";
          event.dataTransfer.setData("text/plain", bar.dataset.ganttTaskId || "");
        });

        bar.addEventListener("dragend", function () {
          bar.classList.remove("dragging");
          if (dragging) dragging.dragged = true;
          setTimeout(function () { dragging = null; }, 0);
        });

        bar.addEventListener("click", function (event) {
          if (bar.dataset.ganttDragged === "true") {
            event.preventDefault();
            delete bar.dataset.ganttDragged;
          }
        });
      });

      timelines.forEach(function (timeline) {
        timeline.addEventListener("dragover", function (event) {
          if (!dragging) return;
          event.preventDefault();
          event.dataTransfer.dropEffect = "move";
          timeline.classList.add("gantt-drop-target");
        });

        timeline.addEventListener("dragleave", function () {
          timeline.classList.remove("gantt-drop-target");
        });

        timeline.addEventListener("drop", function (event) {
          if (!dragging || !rangeStart || !dayCount) return;
          event.preventDefault();
          timeline.classList.remove("gantt-drop-target");
          var rect = timeline.getBoundingClientRect();
          var ratio = Math.max(0, Math.min(0.999999, (event.clientX - rect.left) / rect.width));
          var offset = Math.floor(ratio * dayCount);
          var newStart = addDays(rangeStart, offset);
          var startWasBlank = !dragging.startsOn;
          var duration = dragging.startsOn && dragging.dueOn ? dayDifference(dragging.dueOn, dragging.startsOn) : 0;
          var newDue = addDays(newStart, duration);
          var params = new URLSearchParams();
          params.append("task[lock_version]", dragging.lockVersion || "0");
          if (startWasBlank) {
            params.append("task[due_on]", formatDate(newStart));
          } else {
            params.append("task[starts_on]", formatDate(newStart));
            params.append("task[due_on]", formatDate(newDue));
          }
          var bar = dragging.bar;
          bar.dataset.ganttDragged = "true";
          bar.setAttribute("aria-busy", "true");
          fetch(bar.dataset.ganttUpdateUrl, {
            method: "PATCH",
            credentials: "same-origin",
            headers: {
              "Accept": "text/html",
              "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
              "X-CSRF-Token": csrf ? csrf.content : ""
            },
            body: params.toString()
          }).then(function (response) {
            if (!response.ok) throw new Error("update failed");
            window.location.reload();
          }).catch(function () {
            bar.removeAttribute("aria-busy");
            delete bar.dataset.ganttDragged;
            window.alert("日程を更新できませんでした。タスクを開いて保存してください。");
          });
        });
      });
    });
  }

  setupGanttInteractions();
}());
