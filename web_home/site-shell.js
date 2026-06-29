/**
 * شريط علوي موحّد + قائمة جوال — جميع صفحات mizapos.com
 */
(function () {
  var NAV = [
    { id: "home", href: "index.html", label: "الرئيسية" },
    { id: "screens", href: "index.html#screens", label: "البرنامج" },
    { id: "pricing", href: "pricing/", label: "الأسعار" },
    { id: "programming", href: "programming-services.html", label: "البرمجة" },
    { id: "hosting", href: "web-hosting.html", label: "الاستضافة" },
    { id: "agents", href: "agents.html", label: "وكلاؤنا" },
    { id: "other-apps", href: "other-apps.html", label: "تطبيقات أخرى" },
    { id: "contact", href: "contact.html", label: "اتصل بنا" },
  ];

  function siteBase() {
    var path = window.location.pathname.replace(/\\/g, "/");
    if (/\/pricing\/?$/i.test(path) || /\/pricing\//i.test(path)) {
      return "../";
    }
    return "";
  }

  function esc(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/"/g, "&quot;");
  }

  function renderNav(active) {
    var base = siteBase();
    return NAV.map(function (item) {
      var cls = item.id === active ? ' class="is-active"' : "";
      var isHome = item.href.indexOf("index.html") === 0;
      var path =
        window.location.pathname.replace(/\\/g, "/").split("/").pop() || "index.html";
      var href = base + (isHome && path !== "index.html" && path !== "" ? item.href : item.href);
      return (
        '<a href="' +
        esc(href) +
        '"' +
        cls +
        (item.id === active ? ' aria-current="page"' : "") +
        ">" +
        esc(item.label) +
        "</a>"
      );
    }).join("");
  }

  function mount() {
    var el = document.getElementById("site-header");
    if (!el) return;

    var active = el.getAttribute("data-active") || "home";

    el.innerHTML =
      '<div class="wrap topbar-inner">' +
      '<a href="' + esc(siteBase() + "index.html") + '" class="brand" aria-label="MizaPos — الرئيسية">' +
      '<img class="brand-logo" src="assets/branding/mizapos_logo.png" width="48" height="48" alt="MizaPos" decoding="async" />' +
      "</a>" +
      '<button type="button" class="nav-toggle" id="nav-toggle" aria-expanded="false" aria-controls="site-nav" aria-label="فتح القائمة">' +
      '<span></span><span></span><span></span>' +
      "</button>" +
      '<nav class="nav" id="site-nav" aria-label="أقسام الموقع">' +
      renderNav(active) +
      "</nav>" +
      "</div>";

    var toggle = document.getElementById("nav-toggle");
    var nav = document.getElementById("site-nav");
    if (toggle && nav) {
      toggle.addEventListener("click", function () {
        var open = document.body.classList.toggle("nav-open");
        toggle.setAttribute("aria-expanded", open ? "true" : "false");
      });
      nav.querySelectorAll("a").forEach(function (link) {
        link.addEventListener("click", function () {
          document.body.classList.remove("nav-open");
          toggle.setAttribute("aria-expanded", "false");
        });
      });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mount);
  } else {
    mount();
  }
})();
