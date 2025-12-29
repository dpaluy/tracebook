(function() {
  const STIMULUS_SRC = "https://unpkg.com/@hotwired/stimulus/dist/stimulus.umd.js";
  let booted = false;

  function warnStimulusMissing() {
    if (booted) return;

    console.warn("TraceBook: Stimulus failed to load; keyboard shortcuts disabled.");
    if (document.body) {
      const banner = document.createElement("div");
      banner.className = "tb-alert";
      banner.textContent = "Keyboard navigation is unavailable because Stimulus failed to load.";
      document.body.prepend(banner);
    }
  }

  function startApplication() {
    if (booted || !window.Stimulus) {
      warnStimulusMissing();
      return;
    }

    booted = true;
    const application = window.Stimulus.Application.start();

    class KeyboardController extends window.Stimulus.Controller {
      static get targets() {
        return ["table", "row", "checkbox", "toggleAll", "reviewState"];
      }

      connect() {
        this.index = -1;
        this.element.addEventListener("keydown", this.handleKeydown.bind(this));
        if (this.hasToggleAllTarget) {
          this.toggleAllTarget.addEventListener("change", this.toggleAll.bind(this));
        }
      }

      handleKeydown(event) {
        if (["j", "J"].includes(event.key)) {
          event.preventDefault();
          if (this.index === -1) {
            this.index = 0;
          } else {
            this.index = Math.min(this.rowTargets.length - 1, this.index + 1);
          }
          this.updateSelection();
        }
        if (["k", "K"].includes(event.key)) {
          event.preventDefault();
          if (this.index === -1) {
            this.index = 0;
          } else {
            this.index = Math.max(0, this.index - 1);
          }
          this.updateSelection();
        }
        if ([" ", "Enter"].includes(event.key)) {
          event.preventDefault();
          const checkbox = this.checkboxTargets[this.index];
          if (checkbox) {
            checkbox.checked = !checkbox.checked;
          }
        }
      }

      toggleAll() {
        const checked = this.toggleAllTarget.checked;
        this.checkboxTargets.forEach((checkbox) => {
          checkbox.checked = checked;
        });
      }

      updateSelection() {
        this.rowTargets.forEach((row, idx) => {
          row.classList.toggle("tb-selected", idx === this.index);
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

    application.register("keyboard", KeyboardController);
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
