/* Phone numbers are masked; "Show number" calls the audited reveal endpoint. */
"use strict";
(function () {
  const b = document.getElementById("reveal");
  if (!b) return;
  b.addEventListener("click", async () => {
    b.disabled = true;
    try {
      const r = await api("POST", "/api/v1/dashboard/households/" + encodeURIComponent(b.dataset.household) + "/reveal-phone", { reason: "CALL_FAMILY" });
      document.getElementById("phone").textContent = r.phone_number + " (synthetic)";
      b.remove();
      say(r.phone_number);
    } catch (e) { b.disabled = false; alert(e.message); }
  });
})();
