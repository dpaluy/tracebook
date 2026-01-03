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
        return ["toggleAll", "checkbox", "submitButton"];
      }

      connect() {
        this.updateButtonState();
      }

      toggleAll() {
        const checked = this.toggleAllTarget.checked;
        this.checkboxTargets.forEach((checkbox) => {
          checkbox.checked = checked;
        });
        this.updateButtonState();
      }

      checkboxChanged() {
        this.updateButtonState();
      }

      updateButtonState() {
        const hasSelectedCheckboxes = this.checkboxTargets.some((checkbox) => checkbox.checked);
        this.submitButtonTarget.disabled = !hasSelectedCheckboxes;
      }
    }

    class JsonViewerController extends window.Stimulus.Controller {
      static get targets() {
        return ["content", "icon", "copyBtn", "copyText"];
      }

      static get values() {
        return { collapsed: Boolean };
      }

      connect() {
        if (this.collapsedValue) {
          this.collapse();
        } else {
          this.expand();
        }
      }

      toggle(event) {
        // Don't toggle if clicking the copy button
        if (event.target.closest('.tb-copy-btn')) return;

        if (this.element.classList.contains("tb-collapsed")) {
          this.expand();
        } else {
          this.collapse();
        }
      }

      collapse() {
        this.element.classList.add("tb-collapsed");
        this.element.classList.remove("tb-expanded");
        if (this.hasContentTarget) {
          this.contentTarget.style.display = "none";
        }
        if (this.hasIconTarget) {
          this.iconTarget.textContent = "▶";
        }
      }

      expand() {
        this.element.classList.remove("tb-collapsed");
        this.element.classList.add("tb-expanded");
        if (this.hasContentTarget) {
          this.contentTarget.style.display = "block";
        }
        if (this.hasIconTarget) {
          this.iconTarget.textContent = "▼";
        }
      }

      copy(event) {
        event.stopPropagation();
        const btn = event.currentTarget;
        const payload = btn.dataset.payload;

        navigator.clipboard.writeText(payload).then(() => {
          if (this.hasCopyTextTarget) {
            const originalText = this.copyTextTarget.textContent;
            this.copyTextTarget.textContent = "Copied!";
            setTimeout(() => { this.copyTextTarget.textContent = originalText; }, 2000);
          }
        }).catch(() => {
          console.error("Failed to copy to clipboard");
        });
      }
    }

    class MessageToggleController extends window.Stimulus.Controller {
      static get targets() {
        return ["content", "icon"];
      }

      toggle() {
        const isHidden = this.contentTarget.classList.contains("hidden");
        if (isHidden) {
          this.contentTarget.classList.remove("hidden");
          this.iconTarget.textContent = "▼";
        } else {
          this.contentTarget.classList.add("hidden");
          this.iconTarget.textContent = "▶";
        }
      }
    }

    application.register("bulk-select", BulkSelectController);
    application.register("json-viewer", JsonViewerController);
    application.register("message-toggle", MessageToggleController);
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
