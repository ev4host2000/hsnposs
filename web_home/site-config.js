/**
 * إعدادات الصفحة الرئيسية — https://mizapos.com
 */
window.MIZAPOS_LANDING = {
  windowsDownloadUrl: "https://mizapos.com/download/MizaPos-Setup.exe",
  androidDownloadUrl: "https://mizapos.com/download/MizaPos-Android-app.apk",
  activateUrl: "https://mizapos.com/drhsn/public/vouchers.html",
  pricingUrl: "https://mizapos.com/pricing",
  whatsapp: "970599488939",
  contactApiUrls: [
    "/contact.php",
    "https://mizapos.com/contact.php",
    "https://mizapos.com/drhsn/api/website/contact",
  ],
  contactFormSubmitUrl: "https://formsubmit.co/ajax/hsnpal99@gmail.com",
  otherApps: [
    {
      id: "masareef",
      name: "تطبيق مصاريف",
      description:
        "تطبيق مجاني 100% لتسجيل المصاريف اليومية وتنظيمها بسهولة — بدون اشتراك أو تفعيل.",
      logoUrl: "assets/branding/masareef_app_icon.png",
      androidDownloadUrl: "https://mizapos.com/download/masareef-app.apk",
      androidDownloadName: "masareef-app.apk",
      isFree: true,
    },
  ],
};

(function () {
  var cfg = window.MIZAPOS_LANDING || {};
  var winUrl = (cfg.windowsDownloadUrl || "").trim();
  var apkUrl = (cfg.androidDownloadUrl || "").trim();

  function waHref(num) {
    var n = String(num || "").replace(/\D/g, "");
    return n ? "https://wa.me/" + n : "#";
  }

  function bindDownload(el, url, missingMsg, downloadName) {
    if (!el) return;
    if (url) {
      el.href = url;
      if (downloadName) el.setAttribute("download", downloadName);
      el.rel = "noopener";
      el.target = "_blank";
    } else {
      el.addEventListener("click", function (e) {
        e.preventDefault();
        alert(missingMsg);
      });
    }
  }

  function bindActivate(el) {
    if (!el) return;
    var wa = waHref(cfg.whatsapp);
    if (wa !== "#") {
      var text = encodeURIComponent("مرحباً، أريد تفعيل اشتراك MizaPos");
      el.href = wa + "?text=" + text;
      el.target = "_blank";
      el.rel = "noopener noreferrer";
    } else {
      el.addEventListener("click", function (e) {
        e.preventDefault();
        alert("يُرجى ضبط رقم واتساب في site-config.js");
      });
    }
  }

  function bindSubscribeWa(el) {
    if (!el) return;
    var wa = waHref(cfg.whatsapp);
    if (wa === "#") return;
    var text = encodeURIComponent("مرحباً، أريد الاشتراك في باقة MizaPos (كمبيوتر + جوال)");
    el.addEventListener("click", function (e) {
      e.preventDefault();
      window.open(wa + "?text=" + text, "_blank", "noopener,noreferrer");
    });
  }

  var waHrefVal = waHref(cfg.whatsapp);
  document.querySelectorAll("[data-wa-link]").forEach(function (el) {
    if (el.getAttribute("href") && el.getAttribute("href").indexOf("wa.me") >= 0) return;
    if (waHrefVal !== "#") {
      el.href = waHrefVal;
      el.target = "_blank";
      el.rel = "noopener noreferrer";
    } else {
      el.addEventListener("click", function (e) {
        e.preventDefault();
        alert("يُرجى ضبط رقم واتساب في site-config.js");
      });
    }
  });

  [
    "download-windows",
    "download-windows-2",
  ].forEach(function (id) {
    bindDownload(
      document.getElementById(id),
      winUrl,
      "يُرجى ضبط windowsDownloadUrl في site-config.js",
      "MizaPos-Setup.exe"
    );
  });
  ["download-android", "download-android-2"].forEach(function (id) {
    bindDownload(
      document.getElementById(id),
      apkUrl,
      "يُرجى ضبط androidDownloadUrl في site-config.js",
      "MizaPos-Android-app.apk"
    );
  });

  document.querySelectorAll(".topbar-activate").forEach(bindActivate);
  document.querySelectorAll(".topbar-subscribe").forEach(bindSubscribeWa);

  var masareefApp =
    (cfg.otherApps || []).find(function (a) {
      return a && a.id === "masareef";
    }) || (cfg.otherApps || [])[0];
  if (masareefApp) {
    document.querySelectorAll("[data-download-masareef]").forEach(function (el) {
      bindDownload(
        el,
        String(masareefApp.androidDownloadUrl || "").trim(),
        "رابط تحميل تطبيق المصاريف غير متوفر حالياً.",
        masareefApp.androidDownloadName || "masareef-app.apk"
      );
    });
  }
})();
