// Pageviews and download clicks for the product page.
//
// Nothing leaves the browser until SITE is filled in. With it empty this file
// returns immediately, so an unconfigured page makes no third-party request at
// all — which is what the README promises about the app itself.
//
// To turn it on: sign up at https://goatcounter.com (free, no card), pick a
// code, and put it below. "pricebar" would mean the counter lives at
// https://pricebar.goatcounter.com.
(function () {
  var SITE = ""; // TODO: the GoatCounter site code
  if (!SITE) return;

  var endpoint = "https://" + SITE + ".goatcounter.com/count";

  var loader = document.createElement("script");
  loader.async = true;
  loader.src = "https://gc.zgo.at/count.js";
  loader.setAttribute("data-goatcounter", endpoint);
  document.head.appendChild(loader);

  // Any element with data-track="<name>" is counted as an event. The library
  // may still be loading when someone clicks, so fall back to the plain count
  // endpoint, which answers with a one-pixel image and records the same hit.
  document.addEventListener(
    "click",
    function (event) {
      var target = event.target;
      while (target && target !== document && !target.getAttribute) target = target.parentNode;
      if (!target || target === document) return;
      var name = target.getAttribute("data-track");
      if (!name) return;
      var title = (target.textContent || "").trim();
      if (window.goatcounter && window.goatcounter.count) {
        window.goatcounter.count({ path: name, title: title, event: true });
      } else if (navigator.sendBeacon) {
        var body = new Blob([JSON.stringify([{ path: name, title: title, event: true }])], {
          type: "application/json",
        });
        navigator.sendBeacon(endpoint, body);
      }
    },
    true
  );
})();
