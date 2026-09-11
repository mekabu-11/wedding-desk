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

  setSidebarCollapsed(read(sidebarKey) === "1");
  setTheme(read(themeKey) === "dark" ? "dark" : "light");

  var sidebarButton = document.querySelector("[data-sidebar-toggle]");
  if (sidebarButton) {
    sidebarButton.addEventListener("click", function () {
      var collapsed = !body.classList.contains("sidebar-collapsed");
      setSidebarCollapsed(collapsed);
      write(sidebarKey, collapsed ? "1" : "0");
    });
  }

  var themeButton = document.querySelector("[data-theme-toggle]");
  if (themeButton) {
    themeButton.addEventListener("click", function () {
      var dark = root.dataset.theme !== "dark";
      setTheme(dark ? "dark" : "light");
      write(themeKey, dark ? "dark" : "light");
    });
  }
}());
