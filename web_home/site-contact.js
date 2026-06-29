/**
 * نموذج اتصل بنا — يُستخدم في contact.html
 */
(function () {
  var cfg = window.MIZAPOS_LANDING || {};
  var contactApis = []
    .concat(cfg.contactApiUrls || [])
    .concat(cfg.contactApiUrl ? [cfg.contactApiUrl] : [])
    .map(function (u) {
      return String(u || "").trim();
    })
    .filter(Boolean);
  var formSubmitUrl = (cfg.contactFormSubmitUrl || "").trim();

  function postJson(url, payload) {
    return fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(payload),
    }).then(function (res) {
      return res
        .json()
        .catch(function () {
          return {};
        })
        .then(function (data) {
          return { url: url, status: res.status, data: data };
        });
    });
  }

  function tryContactApis(urls, payload, index) {
    if (index >= urls.length) {
      return Promise.reject(new Error("no_api"));
    }
    return postJson(urls[index], payload).then(function (r) {
      if (r.data && r.data.ok) {
        return r;
      }
      if (r.status === 404 || r.status === 405) {
        return tryContactApis(urls, payload, index + 1);
      }
      return Promise.reject(r);
    });
  }

  function sendViaFormSubmit(payload) {
    if (!formSubmitUrl) {
      return Promise.reject(new Error("no_formsubmit"));
    }
    var fsBody = {
      name: payload.name,
      email: payload.email,
      phone: payload.phone || "",
      message:
        "الموضوع: " +
        payload.topic +
        "\n\n" +
        payload.message +
        "\n\n(أُرسلت من mizapos.com)",
      _subject: "MizaPos — " + payload.topic,
      _replyto: payload.email,
      _captcha: "false",
      _template: "table",
    };
    return fetch(formSubmitUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(fsBody),
    }).then(function (res) {
      return res.json().then(function (data) {
        if (res.ok && (data.success === true || data.success === "true")) {
          return { ok: true, via: "formsubmit" };
        }
        return Promise.reject(data);
      });
    });
  }

  window.MizaPosContact = {
    openTopic: function (topic) {
      var topicSelect = document.getElementById("cf-topic");
      if (!topic || !topicSelect) return;
      var found = false;
      for (var i = 0; i < topicSelect.options.length; i++) {
        if (topicSelect.options[i].value === topic) {
          topicSelect.selectedIndex = i;
          found = true;
          break;
        }
      }
      if (!found) {
        var opt = document.createElement("option");
        opt.value = topic;
        opt.textContent = topic;
        topicSelect.appendChild(opt);
        topicSelect.value = topic;
      }
    },
    bindForm: function (formId) {
      var contactForm = document.getElementById(formId || "contact-form");
      var contactStatus = document.getElementById("contact-form-status");
      var topicSelect = document.getElementById("cf-topic");
      if (!contactForm) return;

      var params = new URLSearchParams(window.location.search);
      var topicParam = params.get("topic");
      if (topicParam) {
        this.openTopic(topicParam);
      }

      contactForm.addEventListener("submit", function (e) {
        e.preventDefault();
        var submitBtn = document.getElementById("contact-form-submit");
        var payload = {
          name: (document.getElementById("cf-name") || {}).value || "",
          email: (document.getElementById("cf-email") || {}).value || "",
          phone: (document.getElementById("cf-phone") || {}).value || "",
          topic: topicSelect ? topicSelect.value : "استفسار عام",
          message: (document.getElementById("cf-message") || {}).value || "",
          company:
            (contactForm.querySelector('[name="company"]') || {}).value || "",
        };
        if (submitBtn) submitBtn.disabled = true;
        if (contactStatus) {
          contactStatus.textContent = "جاري الإرسال…";
          contactStatus.className = "form-status";
        }

        var chain = contactApis.length
          ? tryContactApis(contactApis, payload, 0)
          : Promise.reject(new Error("no_api"));

        chain
          .catch(function () {
            return sendViaFormSubmit(payload);
          })
          .then(function () {
            if (contactStatus) {
              contactStatus.textContent =
                "تم إرسال رسالتك بنجاح. سنتواصل معك قريباً.";
              contactStatus.className = "form-status ok";
            }
            contactForm.reset();
          })
          .catch(function (err) {
            var msg =
              (err && err.data && err.data.message) ||
              "تعذّر الإرسال. جرّب واتساب أو أعد المحاولة لاحقاً.";
            if (contactStatus) {
              contactStatus.textContent = msg;
              contactStatus.className = "form-status err";
            }
          })
          .finally(function () {
            if (submitBtn) submitBtn.disabled = false;
          });
      });
    },
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      window.MizaPosContact.bindForm("contact-form");
    });
  } else {
    window.MizaPosContact.bindForm("contact-form");
  }
})();
