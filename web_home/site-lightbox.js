/**
 * تكبير لقطات الشاشة عند النقر
 */
(function () {
  var overlay = null;
  var imgEl = null;
  var capEl = null;

  function close() {
    if (!overlay) return;
    overlay.classList.remove("is-open");
    overlay.setAttribute("aria-hidden", "true");
    document.body.classList.remove("lightbox-open");
    if (imgEl) imgEl.removeAttribute("src");
  }

  function open(src, alt) {
    if (!overlay) {
      overlay = document.createElement("div");
      overlay.className = "lightbox";
      overlay.setAttribute("role", "dialog");
      overlay.setAttribute("aria-modal", "true");
      overlay.setAttribute("aria-label", "معاينة الصورة");
      overlay.innerHTML =
        '<button type="button" class="lightbox-close" aria-label="إغلاق">&times;</button>' +
        '<figure class="lightbox-figure"><img class="lightbox-img" alt="" /><figcaption class="lightbox-caption"></figcaption></figure>';
      document.body.appendChild(overlay);
      imgEl = overlay.querySelector(".lightbox-img");
      capEl = overlay.querySelector(".lightbox-caption");
      overlay.querySelector(".lightbox-close").addEventListener("click", close);
      overlay.addEventListener("click", function (e) {
        if (e.target === overlay) close();
      });
      document.addEventListener("keydown", function (e) {
        if (e.key === "Escape") close();
      });
    }
    imgEl.src = src;
    imgEl.alt = alt || "";
    capEl.textContent = alt || "";
    overlay.classList.add("is-open");
    overlay.setAttribute("aria-hidden", "false");
    document.body.classList.add("lightbox-open");
  }

  function bindZoomable(root) {
    root.querySelectorAll(".shot-zoom").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var img = btn.querySelector("img");
        var src = btn.getAttribute("data-full") || (img && img.src) || "";
        var alt = btn.getAttribute("data-caption") || (img && img.alt) || "";
        if (src) open(src, alt);
      });
    });
  }

  function init() {
    var screens = document.getElementById("screens");
    if (screens) bindZoomable(screens);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
