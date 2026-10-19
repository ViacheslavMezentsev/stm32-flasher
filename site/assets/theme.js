// Общая тема STM32-сайтов: тёмная по умолчанию, круглая кнопка переключает «тёмная -> светлая -> авто».
// Скрипт подключается в <head> без defer: атрибут data-theme ставится до отрисовки, без вспышки.
// Ключ хранилища общий для всех сайтов на viacheslavmezentsev.github.io: выбор темы один на семейство.
(function () {
  var KEY = "demo-stm32-skills-theme";
  var ORDER = ["dark", "light", "auto"];
  var TEXT = {
    ru: { dark: "Тема: тёмная", light: "Тема: светлая", auto: "Тема: как в системе", next: ". Нажмите, чтобы сменить" },
    en: { dark: "Theme: dark", light: "Theme: light", auto: "Theme: system", next: ". Click to change" }
  };
  var media = window.matchMedia ? window.matchMedia("(prefers-color-scheme: light)") : null;
  var root = document.documentElement;
  var text = TEXT[(root.getAttribute("lang") || "ru").slice(0, 2)] || TEXT.ru;

  function stored() {
    try {
      var value = window.localStorage.getItem(KEY);
      return ORDER.indexOf(value) >= 0 ? value : "dark";
    } catch (error) {
      return "dark";
    }
  }

  function save(value) {
    try {
      window.localStorage.setItem(KEY, value);
    } catch (error) {
      // приватный режим или запрет хранилища: тема действует до перезагрузки
    }
  }

  function apply(pref) {
    var theme = pref === "auto" ? (media && media.matches ? "light" : "dark") : pref;
    root.setAttribute("data-theme", theme);
    root.setAttribute("data-theme-pref", pref);
    var button = document.getElementById("theme-toggle");
    if (button) {
      button.setAttribute("aria-label", text[pref] + text.next);
      button.setAttribute("title", text[pref]);
    }
  }

  var pref = stored();
  apply(pref);

  if (media) {
    var onChange = function () {
      if (pref === "auto") apply(pref);
    };
    if (media.addEventListener) media.addEventListener("change", onChange);
    else if (media.addListener) media.addListener(onChange);
  }

  document.addEventListener("DOMContentLoaded", function () {
    apply(pref);
    var button = document.getElementById("theme-toggle");
    if (!button) return;
    button.addEventListener("click", function () {
      pref = ORDER[(ORDER.indexOf(pref) + 1) % ORDER.length];
      save(pref);
      apply(pref);
    });
  });
})();
