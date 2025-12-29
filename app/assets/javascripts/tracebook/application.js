(function() {
  const STIMULUS_SRC = "https://unpkg.com/@hotwired/stimulus/dist/stimulus.umd.js";
  let booted = false;

  function warnStimulusMissing() {
    if (booted) return;
    console.warn("TraceBook: Stimulus failed to load.");
  }

  function startApplication() {
    if (booted || !window.Stimulus) {
      warnStimulusMissing();
      return;
    }

    booted = true;
    const application = window.Stimulus.Application.start();

    class BulkSelectController extends window.Stimulus.Controller {
      static get targets() {
        return ["toggleAll", "checkbox"];
      }

      toggleAll() {
        const checked = this.toggleAllTarget.checked;
        this.checkboxTargets.forEach((checkbox) => {
          checkbox.checked = checked;
        });
      }
    }

    class JsonViewerController extends window.Stimulus.Controller {
      static get targets() {
        return ["content"];
      }

      toggle() {
        this.element.classList.toggle("tb-collapsed");
      }
    }

    application.register("bulk-select", BulkSelectController);
    application.register("json-viewer", JsonViewerController);
  }

  if (window.Stimulus) {
    startApplication();
  } else {
    const script = document.createElement("script");
    script.src = STIMULUS_SRC;
    script.async = true;
    script.onload = startApplication;
    script.onerror = warnStimulusMissing;
    document.head.appendChild(script);
  }
})();
